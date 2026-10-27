# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DepartureProgress do
  let(:season) { create(:season, year: 2026) }
  let(:team) { create(:team, school: 'Sample School') }
  let(:membership) { create(:team_season, team:, season:) }
  let(:batch) { legacy_departure_batch(season) }

  before do
    membership
    capture_departures(batch)
    save_departure_rows(batch, departure_rows(team))
    operation = Departures::ValidationPreparation.create(batch)
    PrepareDepartureValidationJob.perform_now(operation.id)
    approval = Departures::ValidationApproval.new(operation.reload).call(reviewer: 'reviewer@example.test')
    PublishDepartureValidationJob.perform_now(approval.id)
  end

  def acquired_records(&)
    count = 0
    subscriber = lambda do |*, event|
      count += event.fetch(:record_count) if event[:class_name] == 'DepartureAcquisition'
    end
    ActiveSupport::Notifications.subscribed(subscriber, 'instantiation.active_record', &)
    count
  end

  it 'reads compact revision identity and leaves full evidence retained' do
    progress = described_class.new(season)
    revision = progress.send(:revision)
    expect(revision.attributes.keys).to eq(['id'])
    expect(OffseasonInputRevision.find(revision.id).payload.keys).to include('dataset', 'review')
    expect(progress.call.status).to eq('complete')
  end

  it 'does not replay or select annual source JSON for setup progress' do
    allow(Departures::RetainedEvidence).to receive(:new).and_raise('Source replay forbidden')
    queries = []
    observer = lambda do |*, event|
      queries << event.fetch(:sql) if event.fetch(:sql).include?('SELECT "departure_acquisitions".*')
    end
    ActiveSupport::Notifications.subscribed(observer, 'sql.active_record') do
      records = acquired_records { expect(described_class.new(season).call.status).to eq('complete') }
      expect(records).to eq(0)
    end
    expect(queries).to be_empty
  end

  it 'keeps unsigned historical revisions visible without treating them as current proof' do
    DepartureApproval.delete_all
    DepartureProposal.delete_all
    DepartureValidation.delete_all
    allow(Departures::RetainedEvidence).to receive(:new).and_raise('Source replay forbidden')
    step = described_class.new(season).call
    expect(step.status).to eq('needs_review')
    expect(step.last_result).to include('is retained', 'validation needed')
  end

  it 'checks stale profile pointers and reads acquisition status without instantiating source payloads' do
    membership.team_offseason_profile.update!(departure_revision: nil)
    records = acquired_records do
      progress = described_class.new(season).call
      expect(progress.status).to eq('needs_review')
      expect(progress.last_result).to include('acquisition completed')
    end
    expect(records).to eq(0)
  end

  it 'rejects current identity changes against the signed saved report' do
    team.update!(school: 'Changed canonical identity')
    expect(described_class.new(season).call.status).to eq('needs_review')
  end
end
