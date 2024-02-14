# frozen_string_literal: true

class Game < ApplicationRecord
  validates :url, presence: true
  validates :start_time, presence: true

  belongs_to :season
  has_one :home_team_game, -> { where(home: true) }, inverse_of: :game, class_name: 'TeamGame', dependent: :destroy
  has_one :away_team_game, -> { where(home: false) }, inverse_of: :game, class_name: 'TeamGame', dependent: :destroy
  has_one :home_team, through: :home_team_game, source: :team
  has_one :away_team, through: :away_team_game, source: :team
  has_one :home_team_season, through: :home_team_game, source: :team_season
  has_one :away_team_season, through: :away_team_game, source: :team_season
  has_one :prediction, dependent: :destroy

  enum status: { scheduled: 0, final: 1, canceled: 2 }

  def finalize
    final!

    calculate_possessions
    calculate_neutrality
    calculate_minutes

    home_team_game&.calculate_game_stats
    away_team_game&.calculate_game_stats

    create_prediction if prediction.blank?
  end

  def pace
    ((possessions.to_f / minutes) * 40.0).to_f
  end

  private

  def calculated_possessions
    arr = [home_team_game&.calculated_possessions, away_team_game&.calculated_possessions].compact

    return unless arr.size.positive?

    (arr.sum / arr.size)
  end

  def calculated_minutes
    arr = [home_team_game&.minutes, away_team_game&.minutes].compact

    return unless arr.size.positive?

    (arr.sum / (5 * arr.size))
  end

  def calculated_neutrality
    return unless home_team&.location

    location.exclude?(home_team&.location)
    # && (location != home_team.probable_home_venue)
  end

  def calculate_possessions
    update(possessions: calculated_possessions)
  end

  def calculate_neutrality
    update(neutral: calculated_neutrality)
  end

  def calculate_minutes
    update(minutes: calculated_minutes)
  end

  def create_prediction
    return unless home_team_season && away_team_season

    predictor = ProphetRatings::GamePredictor.new(home_team_season, away_team_season, neutral, season)

    create_prediction!({
      home_offensive_efficiency: predictor.home_expected_ortg,
      home_defensive_efficiency: predictor.home_expected_drtg,
      away_offensive_efficiency: predictor.away_expected_ortg,
      away_defensive_efficiency: predictor.away_expected_drtg,
      home_score: predictor.home_expected_score,
      away_score: predictor.away_expected_score,
      pace: predictor.expected_pace,
      home_offensive_efficiency_error: predictor.home_expected_ortg - home_team_game.offensive_rating,
      home_defensive_efficiency_error: predictor.home_expected_drtg - away_team_game.offensive_rating,
      away_offensive_efficiency_error: predictor.away_expected_ortg - away_team_game.offensive_rating,
      away_defensive_efficiency_error: predictor.away_expected_drtg - home_team_game.offensive_rating,
      pace_error: predictor.expected_pace - pace,
    })
  end
end
