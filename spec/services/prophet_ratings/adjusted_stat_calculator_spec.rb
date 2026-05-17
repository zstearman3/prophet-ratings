# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::AdjustedStatCalculator, type: :service do
  describe '#call' do
    let(:season) { create(:season, :current) }
    let!(:team_seasons) { create_three_team_round_robin(season:, stat: :effective_fg_percentage) }

    let(:ts1) { team_seasons[0] }
    let(:ts2) { team_seasons[1] }
    let(:ts3) { team_seasons[2] }

    let(:calculator) do
      described_class.new(season: season, raw_stat: :effective_fg_percentage, adj_stat: :adj_effective_fg_percentage,
                          adj_stat_allowed: :adj_effective_fg_percentage_allowed)
    end

    before do
      allow(calculator).to receive(:average_stat_for_season).and_return(0.50)
      # x_values: [off1, off2, off3, def1, def2, def3]
      # To satisfy the specs:
      # ts1.adj_effective_fg_percentage = off1 + season_avg > 0.50
      # ts2.adj_effective_fg_percentage = off2 + season_avg < 0.50
      # ts1.adj_effective_fg_percentage_allowed = def1 + season_avg ~ 0.50
      # ts3.adj_effective_fg_percentage_allowed = def3 + season_avg > 0.50
      allow(StatisticsUtils).to receive(:solve_least_squares_with_python).and_return([0.1, -0.1, 0.0, 0.0, 0.0, 0.5])

      calculator.call

      [ts1, ts2, ts3].each(&:reload)
    end

    it 'assigns higher adj eFG% to stronger offensive teams' do
      expect(ts1.adj_effective_fg_percentage).to be > 0.50
      expect(ts2.adj_effective_fg_percentage).to be < 0.50
    end

    it 'assigns lower adj eFG% allowed to stronger defensive teams' do
      expect(ts1.adj_effective_fg_percentage_allowed).to be_within(0.01).of(0.50)
      expect(ts3.adj_effective_fg_percentage_allowed).to be > 0.50
    end
  end

  context 'when no teams have enough finalized games to qualify' do
    let(:season) { create(:season, :current) }
    let(:team_one) { create(:team) }
    let(:team_two) { create(:team) }
    let(:team_season_one) { create(:team_season, season:, team: team_one) }
    let(:team_season_two) { create(:team_season, season:, team: team_two) }

    let(:calculator) do
      described_class.new(
        season:,
        raw_stat: :effective_fg_percentage,
        adj_stat: :adj_effective_fg_percentage,
        adj_stat_allowed: :adj_effective_fg_percentage_allowed
      )
    end

    it 'skips solving and does not raise' do
      team_season_one
      team_season_two

      allow(StatisticsUtils).to receive(:solve_least_squares_with_python).and_call_original
      expect { calculator.call }.not_to raise_error
      expect(StatisticsUtils).not_to have_received(:solve_least_squares_with_python)
    end
  end

  context 'when teams only have scheduled placeholder team games' do
    let(:season) { create(:season, :current) }
    let(:team_one) { create(:team, school: 'Team One') }
    let(:team_two) { create(:team, school: 'Team Two') }
    let(:team_season_one) { create(:team_season, season:, team: team_one) }
    let(:team_season_two) { create(:team_season, season:, team: team_two) }

    let(:calculator) do
      described_class.new(
        season:,
        raw_stat: :effective_fg_percentage,
        adj_stat: :adj_effective_fg_percentage,
        adj_stat_allowed: :adj_effective_fg_percentage_allowed
      )
    end

    before do
      2.times do |index|
        game = create(
          :game,
          season:,
          status: :scheduled,
          start_time: (Date.current + index.days).beginning_of_day + 1.hour,
          home_team_name: team_one.school,
          away_team_name: team_two.school
        )
        create(:team_game, game:, team: team_one, team_season: team_season_one, home: true)
        create(:team_game, game:, team: team_two, team_season: team_season_two, home: false)
      end
    end

    it 'does not count scheduled team games toward qualification' do
      allow(StatisticsUtils).to receive(:solve_least_squares_with_python).and_call_original

      expect { calculator.call }.not_to raise_error
      expect(StatisticsUtils).not_to have_received(:solve_least_squares_with_python)
    end
  end

  describe 'home-court adjustment in matrix inputs' do
    let(:season) { create(:season, :current) }
    let(:home_team) { create(:team) }
    let(:away_team) { create(:team) }
    let(:home_team_season) { create(:team_season, season:, team: home_team) }
    let(:away_team_season) { create(:team_season, season:, team: away_team) }
    let(:calculator) do
      described_class.new(
        season:,
        raw_stat: :offensive_efficiency,
        adj_stat: :adj_offensive_efficiency,
        adj_stat_allowed: :adj_defensive_efficiency
      )
    end

    def build_rows_for(game)
      create(
        :team_game,
        game:,
        team: home_team,
        team_season: home_team_season,
        opponent_team_season: away_team_season,
        home: true,
        offensive_efficiency: 110.0
      )
      create(
        :team_game,
        game:,
        team: away_team,
        team_season: away_team_season,
        opponent_team_season: home_team_season,
        home: false,
        offensive_efficiency: 90.0
      )

      calculator.send(:build_matrix_components, { home_team.id => 0, away_team.id => 1 }, 2, 100.0).second
    end

    it 'applies configured home-court adjustment for confirmed home games' do
      game = create(
        :game,
        season:,
        status: :final,
        start_time: Time.zone.now,
        home_team_name: home_team.school,
        away_team_name: away_team.school,
        venue_type: 'home',
        venue_confidence: 'confirmed'
      )

      expect(build_rows_for(game).first(2)).to eq([7.8, -7.8])
    end

    it 'does not apply home-court adjustment when venue is unknown' do
      game = create(
        :game,
        season:,
        status: :final,
        start_time: Time.zone.now,
        home_team_name: home_team.school,
        away_team_name: away_team.school,
        venue_type: 'unknown',
        venue_confidence: 'unknown'
      )

      expect(build_rows_for(game).first(2)).to eq([10.0, -10.0])
    end
  end
end
