# frozen_string_literal: true

# == Schema Information
#
# Table name: team_conferences
#
#  id              :bigint           not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  conference_id   :bigint           not null
#  end_season_id   :bigint
#  start_season_id :bigint           not null
#  team_id         :bigint           not null
#
# Indexes
#
#  index_team_conferences_on_conference_id          (conference_id)
#  index_team_conferences_on_end_season_id          (end_season_id)
#  index_team_conferences_on_start_season_id        (start_season_id)
#  index_team_conferences_on_team_and_season_range  (team_id,start_season_id,end_season_id) UNIQUE
#  index_team_conferences_on_team_id                (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (conference_id => conferences.id)
#  fk_rails_...  (end_season_id => seasons.id)
#  fk_rails_...  (start_season_id => seasons.id)
#  fk_rails_...  (team_id => teams.id)
#
require 'rails_helper'

RSpec.describe TeamConference do
  let(:team) { create(:team, school: 'Pacific State') }
  let(:conference) { create(:conference, name: 'Old Conference', slug: 'old-conference') }
  let(:other_conference) { create(:conference, name: 'New Conference', slug: 'new-conference') }
  let(:season2025) { create_season(2025) }
  let(:season2026) { create_season(2026) }
  let(:season2027) { create_season(2027) }
  let(:season2028) { create_season(2028) }

  def create_season(year)
    create(
      :season,
      year:,
      name: "#{year - 1}-#{year.to_s.last(2)}",
      start_date: Date.new(year - 1, 11, 1),
      end_date: Date.new(year, 4, 7)
    )
  end

  it 'allows an open-ended range' do
    membership = build(:team_conference, team:, conference:, start_season: season2025)

    expect(membership).to be_valid
  end

  it 'allows a bounded range' do
    membership = build(
      :team_conference,
      team:,
      conference:,
      start_season: season2025,
      end_season: season2026
    )

    expect(membership).to be_valid
  end

  it 'allows adjacent ranges' do
    create(:team_conference, team:, conference:, start_season: season2025, end_season: season2026)
    next_membership = build(:team_conference, team:, conference: other_conference, start_season: season2027)

    expect(next_membership).to be_valid
  end

  it 'allows intentional gaps' do
    create(:team_conference, team:, conference:, start_season: season2025, end_season: season2025)
    later_membership = build(:team_conference, team:, conference: other_conference, start_season: season2027)

    expect(later_membership).to be_valid
  end

  it 'rejects a reversed range' do
    membership = build(:team_conference, team:, conference:, start_season: season2027, end_season: season2026)

    expect(membership).not_to be_valid
    expect(membership.errors[:end_season]).to include('must be the same as or later than the start season')
  end

  it 'rejects an inclusive overlap' do
    create(:team_conference, team:, conference:, start_season: season2025, end_season: season2027)
    overlapping = build(
      :team_conference,
      team:,
      conference: other_conference,
      start_season: season2027,
      end_season: season2028
    )

    expect(overlapping).not_to be_valid
    expect(overlapping.errors[:base]).to include('Conference membership overlaps an existing range')
  end

  it 'rejects an open-ended overlap' do
    create(:team_conference, team:, conference:, start_season: season2025)
    overlapping = build(:team_conference, team:, conference: other_conference, start_season: season2027)

    expect(overlapping).not_to be_valid
    expect(overlapping.errors[:base]).to include('Conference membership overlaps an existing range')
  end

  it 'ignores itself when validating an existing range' do
    membership = create(:team_conference, team:, conference:, start_season: season2025, end_season: season2026)

    membership.end_season = season2027

    expect(membership).to be_valid
  end

  it 'rejects duplicate team and start season keys' do
    create(:team_conference, team:, conference:, start_season: season2025)
    duplicate = build(:team_conference, team:, conference: other_conference, start_season: season2025)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:start_season_id]).to include('has already been taken')
  end

  it 'returns a useful admin label' do
    membership = build(
      :team_conference,
      team:,
      conference:,
      start_season: season2025,
      end_season: season2026
    )

    expect(membership.admin_label).to eq('Pacific State — Old Conference (2025-2026)')
  end
end
