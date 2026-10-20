# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChartDataBuilder do
  describe '#reference_lines' do
    let(:season) do
      instance_double(
        Season,
        avg_adj_offensive_efficiency: nil,
        avg_adj_defensive_efficiency: nil,
        team_seasons: TeamSeason.none
      )
    end
    let(:snapshots) do
      [
        instance_double(TeamRatingSnapshot, snapshot_date: Date.new(2026, 1, 1), rating: 5.0),
        instance_double(TeamRatingSnapshot, snapshot_date: Date.new(2026, 1, 2), rating: 6.0)
      ]
    end

    it 'keeps unavailable rating references nil when season adjusted averages are missing' do
      builder = described_class.new(snapshots: snapshots, season: season, selected_stat: 'rating')

      expect { builder.reference_lines }.not_to raise_error
      expect(builder.reference_lines[:avg].map(&:last)).to eq([nil, nil])
      expect(builder.reference_lines[:upper].map(&:last)).to eq([nil, nil])
    end

    it 'preserves complete references and observed zero values' do
      complete_season = instance_double(Season, avg_adj_offensive_efficiency: 110, avg_adj_defensive_efficiency: 100,
                                                team_seasons: TeamSeason.none)
      builder = described_class.new(snapshots:, season: complete_season, selected_stat: 'rating')

      expect(builder.chart_data.map(&:last)).to eq([5.0, 6.0])
      expect(builder.reference_lines[:avg].map(&:last)).to eq([10.0, 10.0])
      expect(builder.reference_lines[:upper].map(&:last)).to eq([nil, nil])
    end

    it 'preserves complete reference lines and valid zero averages and deviations' do
      zero_season = instance_double(Season, average_pace: 0, pace_std_deviation: 0, team_seasons: TeamSeason.none)
      pace_snapshots = [instance_double(TeamRatingSnapshot, snapshot_date: Date.new(2026, 1, 1), adj_pace: 0),
                        instance_double(TeamRatingSnapshot, snapshot_date: Date.new(2026, 1, 2), adj_pace: 0)]
      builder = described_class.new(snapshots: pace_snapshots, season: zero_season, selected_stat: 'adj_pace')

      expect(builder.reference_lines.values.map { |line| line.map(&:last) }).to all(eq([0.0, 0.0]))
    end

    it 'calculates all reference bands when both season average and deviation are available' do
      complete_season = instance_double(Season, average_pace: 70, pace_std_deviation: 5, team_seasons: TeamSeason.none)
      pace_snapshots = [instance_double(TeamRatingSnapshot, snapshot_date: Date.new(2026, 1, 1), adj_pace: 0)]
      builder = described_class.new(snapshots: pace_snapshots, season: complete_season, selected_stat: 'adj_pace')

      expect(builder.reference_lines.transform_values { |line| line.map(&:last) }).to eq(
        avg: [70], upper: [75], lower: [65], upper2: [80.0], lower2: [60.0]
      )
    end

    it 'keeps snapshot chart values unavailable when a stored metric is nil' do
      sparse_snapshots = [instance_double(TeamRatingSnapshot, snapshot_date: Date.new(2026, 1, 1), rating: nil)]
      builder = described_class.new(snapshots: sparse_snapshots, season:, selected_stat: 'rating')

      expect(builder.chart_data).to eq([[Date.new(2026, 1, 1), nil]])
    end

    it 'keeps unavailable percentage metrics nil without multiplying them' do
      sparse_snapshots = [instance_double(TeamRatingSnapshot, snapshot_date: Date.new(2026, 1, 1),
                                                              adj_effective_fg_percentage: nil)]
      builder = described_class.new(snapshots: sparse_snapshots, season:, selected_stat: 'adj_effective_fg_percentage')

      expect(builder.chart_data).to eq([[Date.new(2026, 1, 1), nil]])
    end
  end
end
