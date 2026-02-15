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

    it 'does not raise when season adjusted averages are nil for rating charts' do
      builder = described_class.new(snapshots: snapshots, season: season, selected_stat: 'rating')

      expect { builder.reference_lines }.not_to raise_error
      expect(builder.reference_lines[:avg].map(&:last)).to eq([0.0, 0.0])
    end
  end
end
