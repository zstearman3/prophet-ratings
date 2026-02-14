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
end
