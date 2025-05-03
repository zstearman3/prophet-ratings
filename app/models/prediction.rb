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
#
# Indexes
#
#  index_predictions_on_away_team_snapshot_id  (away_team_snapshot_id)
#  index_predictions_on_game_id                (game_id)
#  index_predictions_on_home_team_snapshot_id  (home_team_snapshot_id)
#
# Foreign Keys
#
#  fk_rails_...  (away_team_snapshot_id => team_rating_snapshots.id)
#  fk_rails_...  (home_team_snapshot_id => team_rating_snapshots.id)
#
class Prediction < ApplicationRecord
  belongs_to :game
  belongs_to :home_team_snapshot, class_name: 'TeamRatingSnapshot'
  belongs_to :away_team_snapshot, class_name: 'TeamRatingSnapshot'
  has_one :home_team_game, through: :game
  has_one :away_team_game, through: :game
  has_one :season, through: :game

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
        "#{home_score.round + 1} - #{away_score.round}"
      else
        "#{home_score.round} - #{away_score.round + 1}"
      end
    else
      "#{home_score.round} - #{away_score.round}"
    end
  end

  private

  def snapshots_must_have_same_ratings_version
    return if home_team_snapshot.nil? || away_team_snapshot.nil?

    return unless home_team_snapshot.ratings_config_version_id != away_team_snapshot.ratings_config_version_id

    errors.add(:base, 'Home and away team snapshots must use the same ratings config version')
  end
end
