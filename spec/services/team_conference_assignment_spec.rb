# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamConferenceAssignment do
  let(:team) { create(:team, school: 'Realignment U') }
  let(:old_conference) { create(:conference, name: 'Old Conference', slug: 'old-conference') }
  let(:new_conference) { create(:conference, name: 'New Conference', slug: 'new-conference') }
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
      end_date: Date.new(year, 4, 10)
    )
  end

  it 'creates a membership when there is no previous membership' do
    membership = build(:team_conference, team:, conference: new_conference, start_season: season2027)

    expect(described_class.new(membership).call).to be(true)
    expect(membership).to be_persisted
    expect(membership.end_season).to be_nil
  end

  it 'closes an open previous membership at the season before the new start' do
    season2026
    previous = create(:team_conference, team:, conference: old_conference, start_season: season2025)
    membership = build(:team_conference, team:, conference: new_conference, start_season: season2027)

    expect(described_class.new(membership).call).to be(true)

    expect(previous.reload.end_season).to eq(season2026)
    expect(membership).to be_persisted
  end

  it 'truncates a previous membership that extends into the new range' do
    season2026
    previous = create(
      :team_conference,
      team:,
      conference: old_conference,
      start_season: season2025,
      end_season: season2028
    )
    membership = build(:team_conference, team:, conference: new_conference, start_season: season2027)

    expect(described_class.new(membership).call).to be(true)

    expect(previous.reload.end_season).to eq(season2026)
  end

  it 'does not extend an intentional gap' do
    previous = create(
      :team_conference,
      team:,
      conference: old_conference,
      start_season: season2025,
      end_season: season2025
    )
    membership = build(:team_conference, team:, conference: new_conference, start_season: season2027)

    expect(described_class.new(membership).call).to be(true)

    expect(previous.reload.end_season).to eq(season2025)
  end

  it 'retains an explicit end season on the new membership' do
    create(:team_conference, team:, conference: old_conference, start_season: season2025, end_season: season2026)
    membership = build(
      :team_conference,
      team:,
      conference: new_conference,
      start_season: season2027,
      end_season: season2028
    )

    expect(described_class.new(membership).call).to be(true)

    expect(membership.reload.end_season).to eq(season2028)
  end

  it 'adds an error when the preceding season is missing' do
    previous = create(:team_conference, team:, conference: old_conference, start_season: season2025)
    season2027
    Season.where(year: 2026).delete_all
    membership = build(:team_conference, team:, conference: new_conference, start_season: season2027)

    expect(described_class.new(membership).call).to be(false)

    expect(membership.errors[:start_season]).to include('requires the preceding season to close the previous membership')
    expect(previous.reload.end_season).to be_nil
    expect(membership).not_to be_persisted
  end

  it 'rolls back the previous membership closure when the new membership is invalid' do
    season2026
    previous = create(:team_conference, team:, conference: old_conference, start_season: season2025)
    membership = build(
      :team_conference,
      team:,
      conference: new_conference,
      start_season: season2027,
      end_season: season2025
    )

    expect(described_class.new(membership).call).to be(false)

    expect(previous.reload.end_season).to be_nil
    expect(membership.errors[:end_season]).to include('must be the same as or later than the start season')
    expect(membership).not_to be_persisted
  end
end
