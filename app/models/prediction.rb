# frozen_string_literal: true

# == Schema Information
#
# Table name: predictions
#
#  id                              :bigint           not null, primary key
#  away_defensive_efficiency       :decimal(6, 3)
#  away_defensive_efficiency_error :decimal(6, 3)
#  away_offensive_efficiency       :decimal(6, 3)
#  away_offensive_efficiency_error :decimal(6, 3)
#  away_score                      :decimal(6, 3)
#  home_defensive_efficiency       :decimal(6, 3)
#  home_defensive_efficiency_error :decimal(6, 3)
#  home_offensive_efficiency       :decimal(6, 3)
#  home_offensive_efficiency_error :decimal(6, 3)
#  home_score                      :decimal(6, 3)
#  home_win_probability            :decimal(5, 4)
#  pace                            :decimal(6, 3)
#  pace_error                      :decimal(6, 3)
#  vegas_spread                    :decimal(6, 3)
#  vegas_total                     :decimal(6, 3)
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#  away_team_snapshot_id           :bigint
#  game_id                         :bigint           not null
#  home_team_snapshot_id           :bigint
#  ratings_config_version_id       :bigint
#
# Indexes
#
#  index_predictions_on_away_team_snapshot_id      (away_team_snapshot_id)
#  index_predictions_on_game_id                    (game_id)
#  index_predictions_on_home_team_snapshot_id      (home_team_snapshot_id)
#  index_predictions_on_ratings_config_version_id  (ratings_config_version_id)
#
# Foreign Keys
#
#  fk_rails_...  (away_team_snapshot_id => team_rating_snapshots.id)
#  fk_rails_...  (home_team_snapshot_id => team_rating_snapshots.id)
#  fk_rails_...  (ratings_config_version_id => ratings_config_versions.id)
#
class Prediction < ApplicationRecord
  belongs_to :game
  belongs_to :home_team_snapshot, class_name: 'TeamRatingSnapshot'
  belongs_to :away_team_snapshot, class_name: 'TeamRatingSnapshot'
  belongs_to :ratings_config_version
  has_one :home_team_game, through: :game
  has_one :away_team_game, through: :game
  has_one :season, through: :game
  has_many :bet_recommendations, dependent: :destroy

  validates :game, uniqueness: { scope: %i[home_team_snapshot_id away_team_snapshot_id] }
  validate :snapshots_must_have_same_ratings_version

  def favorite
    home_score > away_score ? game.home_team : game.away_team
  end

  def win_probability_for_team(team_id)
    home_team_snapshot.team_id == team_id ? home_win_probability : (1.0 - home_win_probability)
  end

  def favorite_win_probability
    home_score > away_score ? home_win_probability : (1.0 - home_win_probability)
  end

  def total
    ((home_score + away_score) * 2).round / 2.0
  end

  def correct?
    predicted_home_win = home_win_probability >= 0.5
    actual_home_win = game.home_team_score > game.away_team_score

    predicted_home_win == actual_home_win
  end

  def predicted_score_string
    if home_score.round == away_score.round
      if home_score > away_score
        "#{away_score.round} - #{home_score.round + 1}"
      else
        "#{away_score.round + 1} - #{home_score.round}"
      end
    else
      "#{away_score.round} - #{home_score.round}"
    end
  end

  def margin_std_deviation
    pace_factor = (pace**2) / 10_000.0

    var_home = pace_factor * ((home_team_snapshot.team_season.stddev_off**2) + (away_team_snapshot.team_season.stddev_def**2))
    var_away = pace_factor * ((away_team_snapshot.team_season.stddev_off**2) + (home_team_snapshot.team_season.stddev_def**2))

    Math.sqrt(var_home + var_away)
  end

  private

  def snapshots_must_have_same_ratings_version
    return if home_team_snapshot.nil? || away_team_snapshot.nil?

    return unless home_team_snapshot.ratings_config_version_id != away_team_snapshot.ratings_config_version_id

    errors.add(:base, 'Home and away team snapshots must use the same ratings config version')
  end
end
