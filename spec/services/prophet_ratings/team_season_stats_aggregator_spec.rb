require 'rails_helper'

RSpec.describe ProphetRatings::TeamSeasonStatsAggregator, type: :service do
  include StatsHelpers

  describe '#run' do
    let(:team) { create(:team) }
    let(:season) { create(:season) }
    let(:team_season) { create(:team_season, team:, season:) }

    before do
      team_games = create_list(:team_game, 3,
        team: team,
        team_season: team_season,
        field_goals_made: 20,
        field_goals_attempted: 40,
        three_pt_made: 10,
        three_pt_attempted: 18,
        two_pt_made: 10,
        two_pt_attempted: 22,
        offensive_rebounds: 8,
        free_throws_attempted: 12,
        turnovers: 10,
        minutes: 200,
        assists: 12,
        steals: 5,
        blocks: 3
      )

      team_games.each(&:calculate_game_stats)

      described_class.new(season).run
      team_season.reload
    end

    it 'computes effective_fg_percentage correctly' do
      fgm = 20 * 3
      fga = 40 * 3
      three_pm = 10 * 3
      expected = expected_effective_fg_percentage(fgm: fgm, fga: fga, three_pm: three_pm)

      expect(team_season.effective_fg_percentage).to be_within(0.001).of(expected)
    end

    it 'averages turnover_rate across games' do
      individual_rate = expected_turnover_rate(
        tov: 10,
        possessions: expected_possessions(fga: 40, orb: 8, tov: 10, fta: 12)
      )
      expected_avg = individual_rate # all games identical

      expect(team_season.turnover_rate).to be_within(0.001).of(expected_avg)
    end
  end
end
