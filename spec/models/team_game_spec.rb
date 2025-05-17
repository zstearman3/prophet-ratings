# frozen_string_literal: true

# == Schema Information
#
# Table name: team_games
#
#  id                       :bigint           not null, primary key
#  assist_rate              :decimal(6, 5)
#  assists                  :integer
#  block_rate               :decimal(6, 5)
#  blocks                   :integer
#  defensive_rating         :decimal(6, 3)
#  defensive_rebound_rate   :decimal(6, 5)
#  defensive_rebounds       :integer
#  effective_fg_percentage  :decimal(6, 5)
#  field_goals_attempted    :integer
#  field_goals_made         :integer
#  field_goals_percentage   :decimal(6, 5)
#  fouls                    :integer
#  free_throw_rate          :decimal(6, 5)
#  free_throws_attempted    :integer
#  free_throws_made         :integer
#  free_throws_percentage   :decimal(6, 5)
#  home                     :boolean          default(FALSE)
#  minutes                  :integer
#  offensive_rating         :decimal(6, 3)
#  offensive_rebound_rate   :decimal(6, 5)
#  offensive_rebounds       :integer
#  points                   :integer
#  rebound_rate             :decimal(6, 5)
#  rebounds                 :integer
#  steal_rate               :decimal(6, 5)
#  steals                   :integer
#  three_pt_attempt_rate    :decimal(6, 5)
#  three_pt_attempted       :integer
#  three_pt_made            :integer
#  three_pt_percentage      :decimal(6, 5)
#  three_pt_proficiency     :decimal(6, 5)
#  true_shooting_percentage :decimal(6, 5)
#  turnover_rate            :decimal(6, 5)
#  turnovers                :integer
#  two_pt_attempted         :integer
#  two_pt_made              :integer
#  two_pt_percentage        :decimal(6, 5)
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  game_id                  :bigint           not null
#  opponent_team_season_id  :bigint
#  team_id                  :bigint           not null
#  team_season_id           :bigint           not null
#
# Indexes
#
#  index_team_games_on_game_id                  (game_id)
#  index_team_games_on_game_id_and_home         (game_id,home) UNIQUE
#  index_team_games_on_opponent_team_season_id  (opponent_team_season_id)
#  index_team_games_on_team_id                  (team_id)
#  index_team_games_on_team_id_and_game_id      (team_id,game_id) UNIQUE
#  index_team_games_on_team_season_id           (team_season_id)
#
# Foreign Keys
#
#  fk_rails_...  (opponent_team_season_id => team_seasons.id)
#

require 'rails_helper'

RSpec.describe TeamGame do
  describe '#calculate_game_stats' do
    let(:team) { create(:team) }
    let(:season) { create(:season) }
    let(:team_season) { create(:team_season, team:, season:) }
    let(:opponent_team_season) { create(:team_season, season:) }
    let(:game) { create(:game, season:) }

    let(:team_game) do
      create(
        :team_game,
        team:,
        team_season:,
        game:,
        opponent_team_season:,
        field_goals_made: 20,
        field_goals_attempted: 40,
        two_pt_made: 10,
        two_pt_attempted: 20,
        three_pt_made: 10,
        three_pt_attempted: 20,
        free_throws_made: 8,
        free_throws_attempted: 10,
        offensive_rebounds: 10,
        defensive_rebounds: 20,
        assists: 15,
        steals: 5,
        blocks: 3,
        turnovers: 12,
        points: 58,
        minutes: 200
      )
    end

    before { team_game.calculate_game_stats }

    it 'calculates effective field goal percentage' do
      fgm = team_game.field_goals_made
      three_pm = team_game.three_pt_made
      fga = team_game.field_goals_attempted

      expected_efg = expected_effective_fg_percentage(fgm:, three_pm:, fga:)
      expect(team_game.effective_fg_percentage).to be_within(0.001).of(expected_efg)
    end

    it 'calculates true shooting percentage' do
      pts = team_game.points
      fga = team_game.field_goals_attempted
      fta = team_game.free_throws_attempted

      expected_ts = expected_true_shooting_percentage(pts:, fga:, fta:)
      expect(team_game.true_shooting_percentage).to be_within(0.001).of(expected_ts)
    end

    it 'calculates turnover rate' do
      fga = team_game.field_goals_attempted
      orb = team_game.offensive_rebounds
      tov = team_game.turnovers
      fta = team_game.free_throws_attempted

      possessions = expected_possessions(fga:, orb:, tov:, fta:)
      expected_tov_rate = expected_turnover_rate(tov:, possessions:)

      expect(team_game.turnover_rate).to be_within(0.001).of(expected_tov_rate)
    end
  end
end
