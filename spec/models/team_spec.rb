# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Team do
  describe '.matching_school_or_alias' do
    let!(:team) { create(:team, school: 'Test College') }

    it 'matches canonical schools without requiring aliases and returns a chainable relation' do
      expect(described_class.matching_school_or_alias(' test COLLEGE ').where(id: team.id)).to eq([team])
    end

    it 'returns distinct candidates across all alias sources, preserving conflicts' do
      other = create(:team)
      create(:team_alias, team:, source: nil, value: 'Shared label')
      create(:team_alias, team:, source: 'sports_reference', value: ' SHARED LABEL ')
      create(:team_alias, team: other, source: '247sports', value: 'shared label')

      expect(described_class.matching_school_or_alias(' Shared Label ').ids).to eq([team.id, other.id].sort)
    end

    it 'leaves missing, invalid and inexact names unmatched' do
      [nil, '', '  ', 123, 'Test Colledge'].each do |name|
        expect(described_class.matching_school_or_alias(name)).to be_empty
      end
    end
  end

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
