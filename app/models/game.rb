# frozen_string_literal: true

# == Schema Information
#
# Table name: games
#
#  id              :bigint           not null, primary key
#  away_team_name  :string           not null
#  away_team_score :integer
#  home_team_name  :string           not null
#  home_team_score :integer
#  location        :string
#  minutes         :integer
#  neutral         :boolean
#  possessions     :decimal(4, 1)
#  start_time      :datetime         not null
#  status          :integer          default("scheduled"), not null
#  url             :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  season_id       :bigint           not null
#
# Indexes
#
#  index_games_on_season_id  (season_id)
#
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
  has_many :predictions, dependent: :destroy

  enum status: { scheduled: 0, final: 1, canceled: 2 }

  def generate_prediction!
    return unless home_rating_snapshot && away_rating_snapshot

    prediction_hash = ProphetRatings::GamePredictor.new(
      home_rating_snapshot:, 
      away_rating_snapshot:, 
      neutral:, 
      season:
    ).call
    
    Prediction.find_or_initialize_by(
      home_team_snapshot: home_rating_snapshot,
      away_team_snapshot: away_rating_snapshot,
      game: self,
    ).tap do |prediction|
      prediction.home_offensive_efficiency = prediction_hash[:meta][:home_expected_ortg]
      prediction.away_offensive_efficiency = prediction_hash[:meta][:away_expected_ortg]
      prediction.home_defensive_efficiency = prediction_hash[:meta][:away_expected_ortg]
      prediction.away_defensive_efficiency = prediction_hash[:meta][:home_expected_ortg]
      prediction.home_score = prediction_hash[:home_expected_score]
      prediction.away_score = prediction_hash[:away_expected_score]
      prediction.home_win_probability = prediction_hash[:win_probability_home]
      prediction.pace = prediction_hash[:meta][:expected_pace]

      prediction.save!
    end
  end

  def finalize_prediction!
    return unless home_rating_snapshot && away_rating_snapshot
    
    prediction = Prediction.find_by(
      home_team_snapshot: home_rating_snapshot,
      away_team_snapshot: away_rating_snapshot,
      game: self,
    )

    return unless prediction
    
    prediction.home_offensive_efficiency_error = home_team_game.offensive_efficiency - prediction.home_offensive_efficiency
    prediction.away_offensive_efficiency_error = away_team_game.offensive_efficiency - prediction.away_offensive_efficiency
    prediction.home_defensive_efficiency_error = away_team_game.offensive_efficiency - prediction.away_offensive_efficiency
    prediction.away_defensive_efficiency_error = home_team_game.offensive_efficiency - prediction.home_offensive_efficiency
    prediction.pace_error = pace - prediction.pace

    prediction.save!
  end

  def finalize
    final!

    calculate_possessions
    calculate_neutrality
    calculate_minutes

    home_team_game&.calculate_game_stats
    away_team_game&.calculate_game_stats

    finalize_prediction!
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

  def home_rating_snapshot
    ratings_config_version = RatingsConfigVersion.current
    TeamRatingSnapshot
      .where(team_season: home_team_season, ratings_config_version: ratings_config_version)
      .where('snapshot_date <= ?', start_time.to_date)
      .order(snapshot_date: :desc)
      .first
  end

  def away_rating_snapshot
    ratings_config_version = RatingsConfigVersion.current
    TeamRatingSnapshot
      .where(team_season: away_team_season, ratings_config_version: ratings_config_version)
      .where('snapshot_date <= ?', start_time.to_date)
      .order(snapshot_date: :desc)
      .first
  end
end
