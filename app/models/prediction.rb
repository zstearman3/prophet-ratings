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

  private

  def snapshots_must_have_same_ratings_version
    return if home_team_snapshot.nil? || away_team_snapshot.nil?

    return unless home_team_snapshot.ratings_config_version_id != away_team_snapshot.ratings_config_version_id

    errors.add(:base, 'Home and away team snapshots must use the same ratings config version')
  end
end
