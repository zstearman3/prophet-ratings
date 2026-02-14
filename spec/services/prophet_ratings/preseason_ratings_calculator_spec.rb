# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::PreseasonRatingsCalculator, type: :service do
  describe '#call' do
    let(:previous_season) do
      create(
        :season,
        year: 2025,
        start_date: Date.new(2024, 11, 1),
        end_date: Date.new(2025, 4, 10),
        average_efficiency: 106.0,
        average_pace: 69.0,
        avg_adj_offensive_efficiency: 107.0,
        avg_adj_defensive_efficiency: 104.0
      )
    end
    let(:season) do
      create(
        :season,
        :current,
        year: 2026,
        start_date: Date.new(2025, 11, 1),
        end_date: Date.new(2026, 4, 10),
        average_efficiency: 105.0,
        average_pace: 68.0
      )
    end
    let(:team) { create(:team) }
    let(:previous_team_season) do
      create(
        :team_season,
        season: previous_season,
        team: team,
        adj_offensive_efficiency: 112.0,
        adj_defensive_efficiency: 99.0,
        adj_pace: 67.0
      )
    end
    let!(:team_season) { create(:team_season, season:, team:) }
    let(:offseason_profile) do
      create(
        :team_offseason_profile,
        team_season: team_season,
        recruiting_score: 40.0,
        returning_minutes_pct: 0.8,
        manual_adjustment: 1.0
      )
    end

    before do
      previous_team_season
      offseason_profile
      described_class.new(season).call
      team_season.reload
    end

    it 'blends prior adjusted values and applies offseason adjustments for efficiency' do
      # efficiency_adjustment = (40.0 * 0.1) - (5.0 * (1.0 - 0.8)) + 1.0 = 4.0
      expect(team_season.preseason_adj_offensive_efficiency).to eq(111.25)
      expect(team_season.preseason_adj_defensive_efficiency).to eq(89.75)
    end

    it 'blends pace from prior season without offseason pace adjustment' do
      expect(team_season.preseason_adj_pace).to eq(67.3)
    end
  end

  context 'when there is no previous season' do
    let(:season) { create(:season, :current, year: 2026) }
    let!(:team_season) { create(:team_season, season: season) }

    it 'falls back to default baselines' do
      described_class.new(season).call
      team_season.reload

      expect(team_season.preseason_adj_offensive_efficiency).to eq(105.5)
      expect(team_season.preseason_adj_defensive_efficiency).to eq(105.5)
      expect(team_season.preseason_adj_pace).to eq(69.5)
    end
  end
end
