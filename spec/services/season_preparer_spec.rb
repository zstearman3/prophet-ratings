# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SeasonPreparer do
  describe '#call' do
    let!(:teams) { create_list(:team, 3) }

    it 'creates a future season and one TeamSeason per team without changing the current season' do
      current_season = create(
        :season,
        :current,
        year: 2026,
        name: '2025-26',
        start_date: Date.new(2025, 11, 3),
        end_date: Date.new(2026, 4, 6)
      )

      result = described_class.new(year: 2027).call

      season = result.season
      expect(season).to have_attributes(
        year: 2027,
        name: '2026-27',
        start_date: Date.new(2026, 11, 3),
        end_date: Date.new(2027, 4, 6),
        current: false,
        average_efficiency: BigDecimal('105.0'),
        average_pace: BigDecimal('70.0')
      )
      expect(result.team_seasons_created).to eq(3)
      expect(season.team_seasons.pluck(:team_id)).to match_array(teams.map(&:id))
      expect(Season.current).to eq(current_season)
    end

    it 'creates only missing TeamSeason rows on subsequent calls' do
      result = described_class.new(year: 2027).call
      expect(result.team_seasons_created).to eq(3)

      result = described_class.new(year: 2027).call
      expect(result.team_seasons_created).to eq(0)

      new_team = create(:team)
      result = described_class.new(year: 2027).call

      expect(result.team_seasons_created).to eq(1)
      expect(result.season.team_seasons.find_by(team: new_team)).to be_present
    end

    it 'uses explicit date overrides' do
      result = described_class.new(
        year: 2027,
        start_date: Date.new(2026, 10, 15),
        end_date: Date.new(2027, 4, 15)
      ).call

      expect(result.season).to have_attributes(
        start_date: Date.new(2026, 10, 15),
        end_date: Date.new(2027, 4, 15)
      )
    end

    it 'updates stale attributes on an existing season' do
      season = create(
        :season,
        year: 2027,
        name: 'Stale Name',
        start_date: Date.new(2026, 10, 1),
        end_date: Date.new(2027, 5, 1)
      )

      result = described_class.new(year: 2027).call

      expect(result.season).to eq(season)
      expect(result.season).to have_attributes(
        name: '2026-27',
        start_date: Date.new(2026, 11, 1),
        end_date: Date.new(2027, 4, 10)
      )
    end

    it 'raises before writing when the year is invalid' do
      expect do
        described_class.new(year: 0).call
      end.to raise_error(ArgumentError, 'year must be positive')

      expect(Season.count).to eq(0)
      expect(TeamSeason.count).to eq(0)
    end

    it 'raises before writing when the date range is invalid' do
      expect do
        described_class.new(
          year: 2027,
          start_date: Date.new(2027, 4, 15),
          end_date: Date.new(2027, 4, 15)
        ).call
      end.to raise_error(ArgumentError, 'end_date must be after start_date')

      expect(Season.count).to eq(0)
      expect(TeamSeason.count).to eq(0)
    end
  end
end
