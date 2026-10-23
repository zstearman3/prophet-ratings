# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OffseasonSetupProgress do
  it 'returns the same fixed sequence and honest pending states without writing' do
    season = create(:season, year: 2027)
    create(:team_season, season:)
    CoachingReview.create!(year: 2027, discovery_status: 'queued', ready: false)
    expected_keys = %w[prepare memberships recruiting coaching departures preseason schedule activation]

    expect { described_class.new(season).steps }.not_to(change do
      [Season.count, TeamSeason.count, RecruitingBatch.count, CoachingReview.count]
    end)
    steps = described_class.new(season).steps

    expect(steps.map(&:key)).to eq(expected_keys)
    expect(steps.map(&:status)).to include('needs_review', 'manual')
    results = [steps.find { |step| step.key == 'coaching' }.last_result,
               steps.find { |step| step.key == 'memberships' }.last_result,
               steps.last.next_action, steps.find { |step| step.key == 'departures' }.next_action]
    expect(results).to eq(['Discovery queued; 0 pending candidates.',
                           'No participation approval is stored. No reviewed roster is stored.',
                           'Review fresh evidence and retained decisions in readiness, then separately activate season or default model.',
                           'Review departure batches and coverage; select the model in preseason preview.'])
  end

  it 'shows the latest queued recruiting attempt even when no approval exists' do
    season = create(:season, year: 2027)
    queued = RecruitingBatch.create!(season:, source_year: 2026, status: 'queued')

    step = described_class.new(season).steps.find { |entry| entry.key == 'recruiting' }

    expect(step.status).to eq('needs_review')
    expect(step.last_result).to include('No approved recruiting revision', "Latest batch ##{queued.id}: queued")
  end

  it 'does not claim recruiting capture availability outside the provider year range' do
    season = create(:season, year: 1900)

    step = described_class.new(season).steps.find { |entry| entry.key == 'recruiting' }

    expect(step.status).to eq('needs_review')
    expect(step.next_action).to include('does not support this target year')
  end

  it 'marks approved participation stale when dates, aliases or target memberships change' do
    season, team, = reviewed_membership
    original_start_date = season.start_date
    progress = described_class.new(season).steps.find { |step| step.key == 'memberships' }
    expect(progress.status).to eq('complete')

    season.update!(start_date: season.start_date + 1.day)
    expect(described_class.new(season).steps.find { |step| step.key == 'memberships' }.status).to eq('needs_review')

    season.update!(start_date: original_start_date)
    team.team_aliases.destroy_all
    expect(described_class.new(season).steps.find { |step| step.key == 'memberships' }.last_result).to include('aliases')

    create(:team_alias, team:, value: team.school)
    alternate = create(:conference)
    team.team_conferences.sole.update!(conference: alternate)
    step = described_class.new(season).steps.find { |entry| entry.key == 'memberships' }
    expect(step).to have_attributes(
      status: 'needs_review',
      last_result: a_string_including('Membership decisions no longer match current target-year memberships.')
    )
  end

  it 'shows a new membership proposal as unreviewed or stale beside the retained approval' do
    season, = reviewed_membership
    season.update!(membership_proposal: { 'provider' => 'sports_reference', 'source_year' => 2027,
                                          'target_year' => 2027, 'captured_at' => Time.current.iso8601,
                                          'fingerprint' => 'stale', 'issues' => [] })

    step = described_class.new(season).steps.find { |entry| entry.key == 'memberships' }

    expect(step.status).to eq('needs_review')
    expect(step.last_result).to include('Latest proposal is stale', 'retained approval remains separate')
  end

  it 'keeps coaching readiness complete when membership evidence alone becomes stale' do
    season, = reviewed_membership
    review = CoachingReview.create!(year: season.year, ready: true, discovery_status: 'complete')
    season.update!(start_date: season.start_date + 1.day)

    steps = described_class.new(season).steps.index_by(&:key)

    expect(steps.fetch('memberships').status).to eq('needs_review')
    expect(steps.fetch('coaching').status).to eq('complete')
    expect(review.reload.ready?).to be(true)
  end

  it 'detects tampered recruiting source bytes behind a retained approval' do
    season = create(:season, year: 2027)
    team = create(:team, school: 'Test College')
    batch = publish_recruiting(season, team)
    batch.update!(snapshot_bytes: 'tampered source snapshot')

    step = described_class.new(season).steps.find { |entry| entry.key == 'recruiting' }

    expect(step.status).to eq('needs_review')
    expect(step.last_result).to include('Retained approval cannot be verified')
  end

  it 'retains approved recruiting beside a newer failure and detects stale mappings or profile pointers' do
    season = create(:season, year: 2027)
    team = create(:team, school: 'Test College')
    batch = publish_recruiting(season, team)
    step = described_class.new(season).steps.find { |entry| entry.key == 'recruiting' }
    expect(step.status).to eq('complete')

    RecruitingBatch.create!(season:, source_year: 2026, status: 'failed', source_status: 'error', failure_message: 'HTTP 403')
    step = described_class.new(season).steps.find { |entry| entry.key == 'recruiting' }
    expect(step.status).to eq('complete')
    expect(step.last_result).to include('Approved revision', 'Latest batch', 'failed', 'HTTP 403')

    other_team = create(:team)
    batch.entries.sole.update!(team: other_team)
    step = described_class.new(season).steps.find { |entry| entry.key == 'recruiting' }
    expect(step).to have_attributes(
      status: 'needs_review',
      last_result: a_string_including('Current review is stale: source rows, mappings or profile pointers differ.')
    )

    season.team_seasons.create!(team: other_team)
    step = described_class.new(season).steps.find { |entry| entry.key == 'recruiting' }
    expect(step.last_result).to include('Coverage: 1 of 2 team seasons point to this revision')
  end

  it 'reports the latest approved revision after a second publication in the same season' do
    season = create(:season, year: 2027)
    team = create(:team, school: 'Test College')
    team_season = create(:team_season, season:, team:)
    first_batch = publish_recruiting(season, team, snapshot: 'first retained source snapshot')
    first_revision = first_batch.revision

    second_batch = publish_recruiting(season, team, snapshot: 'second retained source snapshot')
    second_revision = second_batch.revision
    step = described_class.new(season).steps.find { |entry| entry.key == 'recruiting' }

    expect(second_revision.id).to be > first_revision.id
    expect(OffseasonInputRevision.where(season:, kind: 'recruiting').order(:id).pluck(:id)).to eq(
      [first_revision.id, second_revision.id]
    )
    expect(team_season.reload.team_offseason_profile.recruiting_revision_id).to eq(second_revision.id)
    expect(step).to have_attributes(status: 'complete',
                                    last_result: a_string_including("Approved revision ##{second_revision.id} retained."))
    expect(step.last_result).not_to include("Approved revision ##{first_revision.id} retained.")
  end

  it 'keeps an older approval visible but pending when a newer recruiting batch is ready for review' do
    season = create(:season, year: 2027)
    team = create(:team, school: 'Test College')
    publish_recruiting(season, team)
    bytes = Rails.root.join('spec/fixtures/recruiting/partial.json').read
    dataset = Recruiting::Dataset.new(bytes, 'new recruiting attempt')
    ready = RecruitingBatch.create!(season:, source_year: 2026, status: 'ready', source_status: 'ok',
                                    extract_bytes: bytes, snapshot_bytes: 'new recruiting attempt',
                                    dataset_revision: dataset.manifest.fetch('dataset_revision'))

    step = described_class.new(season).steps.find { |entry| entry.key == 'recruiting' }

    expect(step.status).to eq('needs_review')
    expect(step.last_result).to include('Approved revision', "Latest batch ##{ready.id}: ready",
                                        'ready for review; retained approval remains separate')
  end

  it 'shows coaching readiness until changed evidence invalidates the stored ready flag' do
    season = create(:season, year: 2027)
    review = CoachingReview.create!(year: 2027, ready: true, discovery_status: 'complete')
    expect(described_class.new(season).steps.find { |step| step.key == 'coaching' }.status).to eq('complete')

    CoachingChange.create!(effective_year: 2027, coach_name: 'Pending coach')

    expect(review.reload.ready?).to be(false)
    step = described_class.new(season).steps.find { |entry| entry.key == 'coaching' }
    expect(step.status).to eq('needs_review')
    expect(step.last_result).to include('1 pending candidates')
  end

  def reviewed_membership
    season = create(:season, year: 2027)
    team = create(:team)
    conference = create(:conference)
    create(:team_season, season:, team:)
    create(:team_alias, team:, value: team.school)
    create(:team_conference, team:, conference:, start_season: season, end_season: season)
    decision = { 'team_id' => team.id, 'choice' => conference.id.to_s, 'status' => 'included', 'reason' => 'reviewed' }
    season.update!(participation_review: {
                     'evidence' => 'roster source', 'reviewed_by' => 'admin@example.com', 'reviewed_at' => Time.current.iso8601,
                     'dates' => { 'start_date' => season.start_date.iso8601, 'end_date' => season.end_date.iso8601,
                                  'evidence' => 'schedule' },
                     'teams' => [{ 'team_id' => team.id, 'status' => 'included', 'reason' => 'reviewed' }],
                     'unresolved_identities' => [], 'membership_decisions' => [decision]
                   })
    [season, team, conference]
  end

  def publish_recruiting(season, team, snapshot: 'retained recruiting fixture')
    bytes = Rails.root.join('spec/fixtures/recruiting/partial.json').read
    dataset = Recruiting::Dataset.new(bytes, snapshot)
    batch = RecruitingBatch.create!(season:, source_year: 2026, status: 'ready', source_status: 'ok',
                                    extract_bytes: bytes, snapshot_bytes: snapshot,
                                    dataset_revision: dataset.manifest.fetch('dataset_revision'))
    Recruiting::Preview.new(dataset, season).call.fetch('rows').each do |row|
      batch.entries.create!(RecruitingEntry.source_attributes(row))
    end
    entry = batch.entries.sole
    review = Recruiting::BatchReview.new(batch)
    review.publish({ 'review_key' => review.review_key, 'confirm' => '1', 'rows' => { entry.id.to_s => { 'team_id' => team.id.to_s } } },
                   reviewer: 'admin@example.com')
    batch.reload
  end
end
