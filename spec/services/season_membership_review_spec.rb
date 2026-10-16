# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SeasonMembershipReview do
  subject(:review) { described_class.new(season) }

  let!(:previous) { create(:season, year: 2026) }
  let!(:season) { create(:season, year: 2027, start_date: Date.new(2026, 11, 1), end_date: Date.new(2027, 4, 10)) }
  let!(:team) { create(:team, school: 'Move U', url: '/cbb/schools/move/men/') }
  let!(:old_conference) { create(:conference, name: 'SEC', slug: 'sec', abbreviation: 'SEC') }
  let!(:conference) { create(:conference, name: 'Big 12', slug: 'big-12', abbreviation: 'B12') }
  let!(:membership) { create(:team_conference, team:, conference: old_conference, start_season: previous) }
  let(:source) do
    [{ team_slug: 'move', team_name: team.school, conference_slug: conference.slug,
       conference_name: conference.name, conference_abbreviation: conference.abbreviation }]
  end
  let(:scraper) do
    instance_double(Scraper::ConferenceStandingsScraper, call: source,
                                                         source_url: 'https://www.sports-reference.com/cbb/seasons/men/2027-standings.html')
  end

  before do
    create(:team_alias, team:, value: team.school)
    SeasonPreparer.new(year: season.year).call
    allow(Scraper::ConferenceStandingsScraper).to receive(:new).with(year: season.year).and_return(scraper)
  end

  def approval
    {
      'proposal_key' => review.proposal_key, 'start_date' => '2026-11-02', 'end_date' => '2027-04-06',
      'evidence' => 'Reviewed target-year standings and official schedule boundaries on 2026-10-15',
      'teams' => season.membership_proposal.fetch('rows').to_h do |row|
        [row.fetch('team_id').to_s, { 'choice' => row.fetch('choice'), 'reason' => '' }]
      end
    }
  end

  def approve(attributes = approval)
    review.apply(attributes, reviewer: 'admin@example.test')
  end

  it 'captures proposed switches and source evidence without applying any domain changes' do
    review.refresh
    row = season.reload.membership_proposal.fetch('rows').sole
    expect(row).to include('previous' => 'SEC', 'proposed' => 'Big 12', 'changed' => true)
    expect(team.conference_for(season)).to eq(old_conference)
    expect(season.participation_review).to eq({})
    expect(season.membership_proposal.fetch('source_rows').sole.fetch('team_slug')).to eq('move')
  end

  it 'applies approved switches, participation and dates together without ratings or activation' do
    review.refresh
    approve
    expect(membership.reload.end_season).to eq(previous)
    expect(team.conference_for(season)).to eq(conference)
    expect(season.reload).to have_attributes(start_date: Date.new(2026, 11, 2), end_date: Date.new(2027, 4, 6), current: false)
    expect(season.participation_review).to include('reviewed_by' => 'admin@example.test', 'unresolved_identities' => [])
    expect([TeamRatingSnapshot.count, PreseasonPrior.count, Prediction.count]).to eq([0, 0, 0])
  end

  it 'marks source absences unresolved and requires an explicit evidenced exclusion' do
    absent = create(:team, school: 'Absent U')
    old = create(:team_conference, team: absent, conference: old_conference, start_season: previous)
    review.refresh
    attributes = approval
    expect { approve(attributes) }.to raise_error(ArgumentError, /Absent U: choose/)
    attributes['teams'][absent.id.to_s] = { 'choice' => 'excluded', 'reason' => 'Official departure announcement reviewed' }
    approve(attributes)
    expect(old.reload.end_season).to eq(previous)
    expect(season.participation_review.fetch('teams')).to include(hash_including('team_id' => absent.id, 'status' => 'excluded'))
    expect(season.rating_team_seasons.pluck(:team_id)).to eq([team.id])
  end

  it 'allows a verified independent while preserving its prior membership history' do
    review.refresh
    attributes = approval
    attributes['teams'][team.id.to_s] = { 'choice' => 'independent', 'reason' => 'Verified independent for target season' }
    approve(attributes)
    expect(team.conference_for(season)).to be_nil
    expect(membership.reload.end_season).to eq(previous)
    expect(season.rating_team_seasons.pluck(:team_id)).to eq([team.id])
  end

  it 'does not rewrite an unchanged membership or its timestamp' do
    membership.update!(conference:)
    review.refresh
    before = membership.attributes
    expect(season.membership_proposal.fetch('rows').sole.fetch('changed')).to be(false)
    approve
    expect(membership.reload.attributes).to eq(before)
  end

  it 'retains approved source evidence and clears the pending proposal' do
    review.refresh
    captured = season.membership_proposal.deep_dup
    attributes = approval
    approve(attributes)
    expect(season.reload.membership_proposal).to eq({})
    expect(season.participation_review.fetch('membership_source')).to eq(captured)
    expect { approve(attributes) }.to raise_error(ArgumentError, /Refresh proposals/)
  end

  it 'retains the prior proposal and memberships on an upstream request failure' do
    review.refresh
    before = season.membership_proposal
    allow(scraper).to receive(:call).and_raise(Scraper::ConferenceStandingsScraper::Error, 'HTTP 403')
    expect { review.refresh }.to raise_error(Scraper::ConferenceStandingsScraper::Error, /403/)
    expect(season.reload.membership_proposal).to eq(before)
    expect(membership.reload.end_season).to be_nil
  end

  it 'rejects empty source data without saving a proposal' do
    source.clear
    expect { review.refresh }.to raise_error(Scraper::ConferenceStandingsScraper::Error, /empty/)
    expect(season.reload.membership_proposal).to eq({})
  end

  it 'shows unknown source schools and blocks approval rather than dropping them from the roster' do
    source << source.first.merge(team_slug: 'new-school', team_name: 'New School')
    review.refresh
    expect(season.membership_proposal.fetch('issues').join).to include('New School')
    expect { approve }.to raise_error(ArgumentError, /Resolve source identities/)
    expect(Team.count).to eq(1)
  end

  it 'blocks ambiguous source conferences' do
    create(:conference, abbreviation: conference.abbreviation)
    review.refresh
    expect { approve }.to raise_error(ArgumentError, /Resolve source identities/)
    expect(team.conference_for(season)).to eq(old_conference)
  end

  it 'rejects approval after the proposal was replaced by another refresh' do
    review.refresh
    attributes = approval
    season.update!(membership_proposal: season.membership_proposal.merge('captured_at' => 'changed'))
    expect { approve(attributes) }.to raise_error(ArgumentError, /Proposal changed/)
  end

  it 'rejects approval after a stored school, alias or membership changed' do
    review.refresh
    attributes = approval
    team.update!(school: 'Renamed U')
    expect { approve(attributes) }.to raise_error(ArgumentError, /Local roster/)
    expect(membership.reload.end_season).to be_nil
  end

  it 'requires every stored team to remain represented at approval' do
    review.refresh
    attributes = approval
    create(:team)
    expect { approve(attributes) }.to raise_error(ArgumentError, /Local roster/)
    expect(season.reload.participation_review).to eq({})
  end

  it 'rejects missing submitted rows instead of treating them as approved' do
    review.refresh
    attributes = approval
    attributes['teams'].clear
    expect { approve(attributes) }.to raise_error(ArgumentError, /every proposed school/)
  end

  it 'rejects unsupported membership values' do
    review.refresh
    attributes = approval
    attributes['teams'][team.id.to_s] = { 'choice' => 'invalid', 'reason' => 'reviewed' }
    expect { approve(attributes) }.to raise_error(ArgumentError, /invalid membership/)
  end

  it 'requires exception evidence when overriding the proposed conference' do
    review.refresh
    attributes = approval
    attributes['teams'][team.id.to_s]['choice'] = 'excluded'
    expect { approve(attributes) }.to raise_error(ArgumentError, /provide a reason/)
  end

  it 'rolls back membership changes and dates when alias coverage fails' do
    review.refresh
    attributes = approval
    team.team_aliases.delete_all
    review.refresh
    attributes['proposal_key'] = review.proposal_key
    expect { approve(attributes) }.to raise_error(ArgumentError, /aliases/)
    expect(membership.reload.end_season).to be_nil
    expect(season.reload.start_date).to eq(Date.new(2026, 11, 1))
    expect(season.participation_review).to eq({})
  end

  it 'rolls back membership changes when the reviewed dates are reversed' do
    review.refresh
    attributes = approval.merge('end_date' => '2026-01-01')
    expect { approve(attributes) }.to raise_error(ArgumentError, /dates/)
    expect(membership.reload.end_season).to be_nil
    expect(team.conference_for(season)).to eq(old_conference)
  end

  it 'updates a target-year membership created by an earlier CLI alignment without rewriting prior history' do
    membership.update!(end_season: previous)
    current = create(:team_conference, team:, conference: old_conference, start_season: season)
    review.refresh
    approve
    expect(current.reload.conference).to eq(conference)
    expect(membership.reload.conference).to eq(old_conference)
    expect(membership.end_season).to eq(previous)
  end

  it 'removes only a target-year membership when an exclusion is explicitly approved' do
    membership.update!(end_season: previous)
    current = create(:team_conference, team:, conference: old_conference, start_season: season)
    other = create(:team, url: '/cbb/schools/other/men/')
    create(:team_alias, team: other, value: other.school)
    SeasonPreparer.new(year: season.year).call
    source << source.first.merge(team_slug: 'other', team_name: other.school)
    review.refresh
    attributes = approval
    attributes['teams'][team.id.to_s] = { 'choice' => 'excluded', 'reason' => 'Verified target-year D1 departure' }
    approve(attributes)
    expect(TeamConference.exists?(current.id)).to be(false)
    expect(membership.reload.conference).to eq(old_conference)
    expect(season.rating_team_seasons.pluck(:team_id)).to eq([other.id])
  end

  it 'rolls back earlier switches if a later membership conflicts with a future range' do
    other = create(:team, school: 'Z Future U', url: '/cbb/schools/future/men/')
    future = create(:season, year: 2028)
    create(:team_conference, team: other, conference:, start_season: future)
    create(:team_alias, team: other, value: other.school)
    SeasonPreparer.new(year: season.year).call
    source << source.first.merge(team_slug: 'future', team_name: other.school)
    review.refresh
    expect { approve }.to raise_error(ActiveRecord::RecordInvalid, /overlaps/)
    expect(membership.reload.end_season).to be_nil
    expect(team.conference_for(season)).to eq(old_conference)
    expect(season.reload.participation_review).to eq({})
  end

  it 'rejects local identity changes during discovery without replacing the existing draft' do
    review.refresh
    before = season.membership_proposal
    allow(scraper).to receive(:call) do
      team.update!(school: 'Changed during fetch')
      source
    end
    expect { review.refresh }.to raise_error(ArgumentError, /changed during discovery/)
    expect(season.reload.membership_proposal).to eq(before)
  end

  it 'preserves the approved roster when a later proposal is fetched' do
    review.refresh
    approve
    before = season.reload.participation_review
    review.refresh
    expect(season.reload.participation_review).to eq(before)
    expect(season.membership_proposal).to be_present
  end

  it 'rejects a blank review submission without changing any memberships' do
    review.refresh
    expect { approve({}) }.to raise_error(ArgumentError, /Incomplete review/)
    expect(membership.reload.end_season).to be_nil
  end

  it 'refuses to refresh or approve once the season has published outputs' do
    review.refresh
    attributes = approval
    season.team_seasons.sole.update!(adj_pace: 70)
    expect { approve(attributes) }.to raise_error(ArgumentError, /existing season outputs/)
    expect { review.refresh }.to raise_error(ArgumentError, /existing season outputs/)
  end
end
