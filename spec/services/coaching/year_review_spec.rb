# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Coaching::YearReview do
  let(:workflow) { described_class.new(2027) }
  let(:team) { create(:team) }
  let(:candidate) { CoachingChange.create!(effective_year: 2027, team:, coach_name: 'Incoming Coach') }

  def submission(rows = {})
    { 'review_key' => workflow.review_key, 'confirm' => '1', 'rows' => rows }
  end

  it 'saves reviewed decisions and explicitly marks the whole year ready without a Season' do
    values = { candidate.id.to_s => { 'status' => 'confirmed' } }
    workflow.save(submission(values), intent: 'ready')
    expect(candidate.reload).to be_confirmed
    expect(workflow.review).to be_ready
    expect([Season.count, TeamSeason.count, TeamOffseasonProfile.count, TeamRatingSnapshot.count]).to eq([0, 0, 0, 0])
  end

  it 'allows an intentionally empty year to be marked ready' do
    workflow.save(submission, intent: 'ready')
    expect(workflow.review).to be_ready
  end

  it 'keeps incomplete prior history unknown rather than asserting eligibility' do
    values = { candidate.id.to_s => { 'status' => 'confirmed' } }
    workflow.save(submission(values), intent: 'save')
    expect(candidate.reload).to have_attributes(previous_year: nil, previous_role: nil,
                                                full_season_head_coach: false, previous_season_d1: false)
    expect(workflow.review).not_to be_ready
  end

  it 'requires explicit review confirmation for edits to confirmed facts' do
    candidate.update!(status: 'confirmed')
    values = { candidate.id.to_s => { 'coach_name' => 'Corrected Coach' } }
    attributes = submission(values)
    expect { workflow.save(attributes.merge('confirm' => '0'), intent: 'save') }.to raise_error(ArgumentError, /Confirm/)
    workflow.save(attributes, intent: 'save')
    expect(candidate.reload.coach_name).to eq('Corrected Coach')
  end

  it 'saves a page while keeping other pending candidates unready' do
    values = { candidate.id.to_s => { 'status' => 'confirmed' } }
    other = CoachingChange.create!(effective_year: 2027)
    expect { workflow.save(submission(values), intent: 'ready') }.to raise_error(ActiveRecord::RecordInvalid, /every pending/)
    expect(candidate.reload.status).to eq('pending')
    workflow.save(submission(values), intent: 'save')
    expect(candidate.reload).to be_confirmed
    expect(other.reload.status).to eq('pending')
    expect(workflow.review).not_to be_ready
  end

  it 'rejects stale reviews after a concurrent fact, readiness or source-status change' do
    candidate
    stale = submission
    candidate.update!(coach_name: 'Changed elsewhere')
    expect { workflow.save(stale, intent: 'ready') }.to raise_error(ArgumentError, /changed/)
    stale = submission
    CoachingReview.create!(year: 2027, discovery_status: 'queued')
    expect { workflow.save(stale, intent: 'ready') }.to raise_error(ArgumentError, /changed/)
  end

  it 'does not allow another year or discovery fields to be changed through review rows' do
    values = { candidate.id.to_s => { 'effective_year' => 2028, 'discovery_coach_name' => 'Injected', 'status' => 'rejected' } }
    workflow.save(submission(values), intent: 'save')
    expect(candidate.reload).to have_attributes(effective_year: 2027, discovery_coach_name: nil, status: 'rejected')
    foreign = CoachingChange.create!(effective_year: 2028)
    expect { workflow.save(submission(foreign.id.to_s => { 'status' => 'rejected' }), intent: 'save') }
      .to raise_error(ArgumentError, /from this year/)
    expect(foreign.reload.status).to eq('pending')
  end

  it 'preserves the existing history and confirmed-team uniqueness validations atomically' do
    values = { candidate.id.to_s => { 'status' => 'confirmed', 'full_season_head_coach' => '1' } }
    expect { workflow.save(submission(values), intent: 'ready') }.to raise_error(ActiveRecord::RecordInvalid, /Previous/)
    expect(candidate.reload).not_to be_full_season_head_coach
    CoachingChange.create!(effective_year: 2027, team:, coach_name: 'Another Coach', status: 'confirmed')
    values[candidate.id.to_s] = { 'status' => 'confirmed' }
    expect { workflow.save(submission(values), intent: 'ready') }.to raise_error(ActiveRecord::RecordInvalid, /taken/)
    expect(candidate.reload.status).to eq('pending')
  end

  it 'refuses new readiness while discovery is running or failed' do
    %w[queued fetching failed].each do |status|
      record = CoachingReview.find_or_create_by!(year: 2027)
      record.update!(discovery_status: status)
      expect { workflow.save(submission, intent: 'ready') }.to raise_error(ArgumentError, /successful discovery/)
    end
  end

  it 'queues discovery once while a year is already queued' do
    allow(DiscoverCoachingChangesJob).to receive(:perform_later)
    2.times { workflow.queue_discovery }
    expect(DiscoverCoachingChangesJob).to have_received(:perform_later).with(workflow.review.id).once
    expect(workflow.review.discovery_status).to eq('queued')
  end

  it 'shows source conflicts and source absences without overwriting reviewed facts' do
    candidate.update!(status: 'confirmed', discovery_school: 'source school', discovery_coach_name: 'Different Coach',
                      discovery_team_id: team.id, discovery_present: false)
    warnings = described_class.source_warnings(candidate)
    expect(warnings).to include('Absent from latest successful source fetch', 'Source incoming coach differs from saved facts')
    expect(candidate.reload.coach_name).to eq('Incoming Coach')
  end
end
