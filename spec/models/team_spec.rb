# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Team do
  describe '#conference_for' do
    let(:team) { create(:team) }
    let(:conference) { create(:conference, name: 'Range Conference', slug: 'range-conference') }
    let(:season2024) { create_season(2024) }
    let(:season2025) { create_season(2025) }
    let(:season2026) { create_season(2026) }
    let(:season2027) { create_season(2027) }

    def create_season(year)
      create(
        :season,
        year:,
        name: "#{year - 1}-#{year.to_s.last(2)}",
        start_date: Date.new(year - 1, 11, 1),
        end_date: Date.new(year, 4, 10)
      )
    end

    it 'returns the conference only inside the inclusive membership range' do
      create(:team_conference, team:, conference:, start_season: season2025, end_season: season2026)

      expect(team.conference_for(season2024)).to be_nil
      expect(team.conference_for(season2025)).to eq(conference)
      expect(team.conference_for(season2026)).to eq(conference)
      expect(team.conference_for(season2027)).to be_nil
    end

    it 'returns nil for a nil season' do
      expect(team.conference_for(nil)).to be_nil
    end
  end
end
