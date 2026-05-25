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
#  index_predictions_on_game_and_snapshots         (game_id,home_team_snapshot_id,away_team_snapshot_id) UNIQUE
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
require 'rails_helper'

RSpec.describe Prediction do
  describe '#favorite' do
    it 'uses the game team-game associations' do
      season = create(:season)
      game = create(:game, season:)
      home_team = create(:team)
      away_team = create(:team)
      home_team_season = create(:team_season, team: home_team, season:)
      away_team_season = create(:team_season, team: away_team, season:)
      ratings_config_version = create(:ratings_config_version)
      home_snapshot = create(:team_rating_snapshot, team_season: home_team_season, ratings_config_version:)
      away_snapshot = create(:team_rating_snapshot, team_season: away_team_season, ratings_config_version:)
      create(:team_game, game:, team: home_team, team_season: home_team_season, home: true)
      create(:team_game, game:, team: away_team, team_season: away_team_season, home: false)
      prediction = create(
        :prediction,
        game:,
        home_team_snapshot: home_snapshot,
        away_team_snapshot: away_snapshot,
        ratings_config_version:,
        home_score: 72,
        away_score: 68
      )

      expect(prediction.favorite).to eq(home_team)
    end
  end
end
