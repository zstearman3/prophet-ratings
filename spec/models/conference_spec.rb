# frozen_string_literal: true

# == Schema Information
#
# Table name: conferences
#
#  id           :bigint           not null, primary key
#  abbreviation :string
#  name         :string           not null
#  slug         :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_conferences_on_name  (name)
#  index_conferences_on_slug  (slug)
#
require 'rails_helper'

RSpec.describe Conference do
  describe '#team_seasons_for_season' do
    let(:team) { create(:team) }
    let(:conference) { create(:conference, name: 'Range Conference', slug: 'range-conference') }
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

    it 'returns team seasons only inside the inclusive membership range' do
      create(:team_conference, team:, conference:, start_season: season2025, end_season: season2026)
      team_season2026 = create(:team_season, team:, season: season2026)
      create(:team_season, team:, season: season2027)

      expect(conference.team_seasons_for_season(season2026)).to contain_exactly(team_season2026)
      expect(conference.team_seasons_for_season(season2027)).to be_empty
    end

    it 'returns no team seasons for a nil season' do
      expect(conference.team_seasons_for_season(nil)).to be_empty
    end
  end
end
