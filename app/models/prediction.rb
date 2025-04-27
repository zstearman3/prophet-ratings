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
  has_one :home_team_game, through: :game
  has_one :away_team_game, through: :game
  has_one :season, through: :game
end
