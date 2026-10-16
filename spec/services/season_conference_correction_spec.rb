# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SeasonConferenceCorrection do
  subject(:correction) { described_class.new(season) }

  let!(:previous) { create(:season, year: 2025) }
  let!(:season) { create(:season, year: 2026, current: true) }
  let!(:following) { create(:season, year: 2027) }
  let!(:team) { create(:team, url: '/cbb/schools/correction/men/') }
  let!(:old_conference) { create(:conference, name: 'SEC') }
  let!(:conference) { create(:conference, name: 'Big 12', slug: 'big-12', abbreviation: 'B12') }
  let!(:membership) { create(:team_conference, team:, conference: old_conference, start_season: previous) }
  let!(:row) { create(:team_season, team:, season:, adj_offensive_efficiency: 105, adj_defensive_efficiency: 97, adj_pace: 70) }
  let(:scraper) do
    instance_double(Scraper::ConferenceStandingsScraper, source_url: 'https://example.test/2026-standings.html', call: [
                      { team_slug: 'correction', team_name: team.school, conference_slug: conference.slug,
                        conference_name: conference.name, conference_abbreviation: conference.abbreviation }
                    ])
  end

  before do
    allow(Scraper::ConferenceStandingsScraper).to receive(:new).with(year: 2026).and_return(scraper)
    SeasonMembershipReview.new(season).refresh
  end

  def submission
    { 'proposal_key' => SeasonMembershipReview.new(season).proposal_key,
      'confirm_memberships_only' => '1', 'evidence' => 'Reviewed official 2026 membership records',
      'teams' => { team.id.to_s => { 'selected' => '1', 'choice' => conference.id.to_s } } }
  end

  def apply(attributes = submission)
    correction.call(attributes, reviewer: 'admin@example.test')
  end

  it 'corrects only the target year and preserves both surrounding years' do
    apply
    expect([previous, season, following].map { |year| team.conference_for(year) }).to eq([old_conference, conference, old_conference])
    expect(membership.reload.end_season).to eq(previous)
    expect(season.reload).to be_current
    expect(row.reload.adj_pace).to eq(70)
  end

  it 'requires target-year verification for conference-only corrections from the previous source year' do
    prior = instance_double(Scraper::ConferenceStandingsScraper, call: scraper.call, source_url: 'https://example.test/2025-standings.html')
    allow(Scraper::ConferenceStandingsScraper).to receive(:new).with(year: 2025).and_return(prior)
    SeasonMembershipReview.new(season).refresh(source_year: 2025)
    attributes = submission
    expect { apply(attributes) }.to raise_error(ArgumentError, /Confirm target-year verification/)
    attributes['confirm_target_year'] = '1'
    apply(attributes)
    expect(season.reload.membership_corrections.sole).to include('target_year_confirmed' => true)
  end

  it 'does not need a following boundary when the old range already ends at the target year' do
    membership.update!(end_season: season)
    following.destroy!
    SeasonMembershipReview.new(season).refresh
    apply
    expect(team.conference_for(previous)).to eq(old_conference)
    expect(team.conference_for(season)).to eq(conference)
    expect(TeamConference.find_by!(team:, start_season: season).end_season).to eq(season)
  end

  it 'requires the preceding boundary to preserve an earlier range' do
    earlier = create(:season, year: 2024)
    membership.update!(start_season: earlier)
    previous.destroy!
    SeasonMembershipReview.new(season).refresh
    expect { apply }.to raise_error(ArgumentError, /boundary season YEAR=2025/)
    expect(membership.reload.end_season).to be_nil
    expect(season.reload.membership_corrections).to eq([])
  end

  it 'leaves unrelated later memberships and finite range boundaries intact' do
    membership.update!(end_season: following)
    later = create(:season, year: 2028)
    later_membership = create(:team_conference, team:, conference:, start_season: later)
    before = later_membership.attributes
    SeasonMembershipReview.new(season).refresh
    apply
    expect(team.conference_for(following)).to eq(old_conference)
    expect(TeamConference.find_by!(team:, start_season: following).end_season).to eq(following)
    expect(later_membership.reload.attributes).to eq(before)
  end

  it 'rolls back earlier selected changes and the audit if a later selected school cannot be corrected' do
    membership.update!(end_season: season)
    following.destroy!
    other = create(:team)
    create(:team_conference, team: other, conference: old_conference, start_season: season)
    SeasonMembershipReview.new(season).refresh
    attributes = submission
    attributes['teams'][other.id.to_s] = { 'selected' => '1', 'choice' => conference.id.to_s, 'reason' => 'Verified membership' }
    expect { apply(attributes) }.to raise_error(ArgumentError, /boundary season YEAR=2027/)
    expect(membership.reload.end_season).to eq(season)
    expect(team.conference_for(season)).to eq(old_conference)
    expect(season.reload.membership_corrections).to eq([])
    expect(TeamConference.count).to eq(2)
  end

  it 'records source, reviewer, scope, before/after memberships and evidence without changing participation or dates' do
    season.update!(participation_review: {
                     'evidence' => 'Previously reviewed roster', 'reviewed_by' => 'original@example.test',
                     'teams' => [{ 'team_id' => team.id, 'status' => 'included', 'reason' => 'Verified participant' }],
                     'unresolved_identities' => [],
                     'dates' => { 'start_date' => season.start_date.iso8601, 'end_date' => season.end_date.iso8601,
                                  'evidence' => 'Original date evidence' }
                   })
    SeasonMembershipReview.new(season).refresh
    before = season.attributes.slice('participation_review', 'start_date', 'end_date')
    apply
    audit = season.reload.membership_corrections.sole
    expect(audit).to include('scope' => 'conference_only', 'reviewed_by' => 'admin@example.test', 'target_year' => 2026)
    expect(audit.fetch('memberships_before').size).to eq(1)
    expect(audit.fetch('memberships_after').size).to eq(3)
    expect(audit.fetch('source')).to include('source_year' => 2026)
    expect(season.attributes.slice('participation_review', 'start_date', 'end_date')).to eq(before)
  end

  it 'preserves published snapshots, predictions, live values and stored game conference flags' do
    version = create(:ratings_config_version)
    snapshot = create(:team_rating_snapshot, team_season: row, ratings_config_version: version)
    game = create(:game, season:, in_conference: true)
    prediction = create(:prediction, game:, home_team_snapshot: snapshot, away_team_snapshot: snapshot, ratings_config_version: version)
    records = [row, snapshot, game, prediction]
    before = records.map(&:attributes)
    SeasonMembershipReview.new(season).refresh
    apply
    expect(records.map { |record| record.reload.attributes }).to eq(before)
  end

  it 'does not require decisions for other stored schools or alias coverage' do
    other = create(:team)
    SeasonMembershipReview.new(season).refresh
    apply
    expect(team.conference_for(season)).to eq(conference)
    expect(other.team_conferences).to be_empty
    expect(team.team_aliases).to be_empty
  end

  it 'preserves future history when the existing range begins in the target year' do
    membership.update!(start_season: season)
    SeasonMembershipReview.new(season).refresh
    apply
    expect(team.conference_for(season)).to eq(conference)
    expect(team.conference_for(following)).to eq(old_conference)
    expect(membership.reload.start_season).to eq(following)
  end

  it 'allows removing a target-year conference without declaring the team excluded from participation' do
    attributes = submission
    attributes['teams'][team.id.to_s].merge!('choice' => 'independent', 'reason' => 'Verified independent')
    apply(attributes)
    expect(team.conference_for(season)).to be_nil
    expect(team.conference_for(previous)).to eq(old_conference)
    expect(team.conference_for(following)).to eq(old_conference)
    expect(season.reload.participation_review).to eq({})
  end

  it 'fails without modifying ranges or audit when a required boundary season is missing' do
    following.destroy!
    SeasonMembershipReview.new(season).refresh
    expect { apply }.to raise_error(ArgumentError, /boundary season YEAR=2027/)
    expect(membership.reload.end_season).to be_nil
    expect(season.reload.membership_corrections).to eq([])
  end

  it 'requires selection, explicit conference-only confirmation and evidence' do
    expect { apply(submission.merge('teams' => {})) }.to raise_error(ArgumentError, /Select at least one/)
    expect { apply(submission.merge('confirm_memberships_only' => '0')) }.to raise_error(ArgumentError, /Confirm conference-only scope/)
    expect { apply(submission.merge('evidence' => '')) }.to raise_error(ArgumentError, /provide correction evidence/)
    expect(membership.reload.end_season).to be_nil
  end

  it 'rejects N/A participation changes in a conference-only action' do
    attributes = submission
    attributes['teams'][team.id.to_s].merge!('choice' => 'excluded', 'reason' => 'Verified departure')
    expect { apply(attributes) }.to raise_error(ArgumentError, %r{N/A changes participation})
    expect(season.reload.participation_review).to eq({})
  end

  it 'rejects stale proposals and unknown selected school IDs' do
    attributes = submission
    expect { apply(attributes.merge('proposal_key' => 'stale')) }.to raise_error(ArgumentError, /Proposal changed/)
    attributes['teams']['999999'] = { 'selected' => '1', 'choice' => conference.id.to_s }
    expect { apply(attributes) }.to raise_error(ArgumentError, /Incomplete correction/)
    expect(membership.reload.end_season).to be_nil
  end

  it 'retains closed audit records across later corrections and refuses replay after approval' do
    attributes = submission
    apply(attributes)
    first = season.reload.membership_corrections.sole
    expect { apply(attributes) }.to raise_error(ArgumentError, /Refresh proposals/)
    SeasonMembershipReview.new(season).refresh
    apply
    expect(season.reload.membership_corrections.first).to eq(first)
    expect(season.membership_corrections.size).to eq(2)
  end
end
