# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SeasonMembershipAssignment do
  let!(:previous) { create(:season, year: 2026) }
  let!(:season) { create(:season, year: 2027) }
  let!(:team) { create(:team) }
  let(:conference) { create(:conference) }
  let(:old) { create(:conference) }
  let(:following) { create(:season, year: 2028) }
  let(:later) { create(:season, year: 2029) }

  def assign(choice = conference.id.to_s)
    Season.transaction { described_class.new(season).call([{ 'team_id' => team.id, 'choice' => choice }]) }
  end

  it 'creates an open-ended first membership without preparing the following season' do
    assign
    membership = team.team_conferences.sole
    expect(membership).to have_attributes(conference_id: conference.id, start_season_id: season.id, end_season_id: nil)
    expect(membership.covers_year?(2035)).to be(true)
    expect(Season.exists?(year: 2028)).to be(false)
  end

  it 'closes the previous open membership and carries the approved conference forward' do
    history = create(:team_conference, team:, conference: old, start_season: previous)
    assign
    expect(history.reload).to have_attributes(conference_id: old.id, start_season_id: previous.id, end_season_id: previous.id)
    expect(team.conference_for(season)).to eq(conference)
    expect(team.team_conferences.find_by!(start_season: season).end_season).to be_nil
    expect(Season.exists?(year: 2028)).to be(false)
  end

  it 'preserves an active finite end and a distinct future change with all its metadata' do
    history = create(:team_conference, team:, conference: old, start_season: previous, end_season: following)
    future = create(:team_conference, team:, conference: old, start_season: later)
    retained = future.attributes
    assign
    expect(history.reload.end_season).to eq(previous)
    expect([previous, season, following, later].map { |year| team.conference_for(year) }).to eq([old, conference, conference, old])
    expect(team.team_conferences.find_by!(start_season: season).end_season).to eq(following)
    expect(future.reload.attributes).to eq(retained)
  end

  it 'retains a deliberate gap after a finite end' do
    create(:team_conference, team:, conference: old, start_season: previous, end_season: season)
    future = create(:team_conference, team:, conference: old, start_season: later)
    retained = future.attributes
    assign
    expect([season, following, later].map { |year| team.conference_for(year) }).to eq([conference, nil, old])
    expect(future.reload.attributes).to eq(retained)
  end

  it 'bounds a first membership before an explicit future start without merging the future record' do
    later_membership = create(:team_conference, team:, conference:, start_season: later)
    future = create(:team_conference, team:, conference: old, start_season: following, end_season: following)
    retained = [future.attributes, later_membership.attributes]
    assign
    expect(team.team_conferences.find_by!(start_season: season).end_season).to eq(season)
    expect([future.reload.attributes, later_membership.reload.attributes]).to eq(retained)
    expect(TeamConference.count).to eq(3)
  end

  it 'uses the stored preceding boundary when the next explicit change is more than one year away' do
    following
    future = create(:team_conference, team:, conference: old, start_season: later)
    retained = future.attributes
    assign
    expect([season, following, later].map { |year| team.conference_for(year) }).to eq([conference, conference, old])
    expect(team.team_conferences.find_by!(start_season: season).end_season).to eq(following)
    expect(future.reload.attributes).to eq(retained)
  end

  it 'fails without writes when a boundary needed for a stored future change is missing' do
    future = create(:team_conference, team:, conference: old, start_season: later)
    retained = future.attributes
    expect { assign }.to raise_error(ArgumentError, /boundary season YEAR=2028.*future/)
    expect(future.reload.attributes).to eq(retained)
    expect(TeamConference.count).to eq(1)
    expect(Season.exists?(year: 2028)).to be(false)
  end

  it 'keeps unchanged bounded memberships and timestamps intact' do
    membership = create(:team_conference, team:, conference:, start_season: previous, end_season: following)
    retained = membership.attributes
    assign
    expect(membership.reload.attributes).to eq(retained)
  end

  %w[independent excluded].each do |choice|
    it "ends the active conference for #{choice} without restoring it or changing a later explicit membership" do
      history = create(:team_conference, team:, conference: old, start_season: previous, end_season: following)
      future = create(:team_conference, team:, conference:, start_season: later)
      retained = future.attributes
      assign(choice)
      expect(history.reload.end_season).to eq(previous)
      expect([previous, season, following, later].map { |year| team.conference_for(year) }).to eq([old, nil, nil, conference])
      expect(future.reload.attributes).to eq(retained)
    end

    it "removes a target-starting membership for #{choice} while retaining prior and future records" do
      history = create(:team_conference, team:, conference: old, start_season: previous, end_season: previous)
      target = create(:team_conference, team:, conference: old, start_season: season, end_season: season)
      future = create(:team_conference, team:, conference:, start_season: following)
      retained = [history.attributes, future.attributes]
      assign(choice)
      expect(TeamConference.exists?(target.id)).to be(false)
      expect([history.reload.attributes, future.reload.attributes]).to eq(retained)
    end
  end
end
