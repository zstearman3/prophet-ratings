# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::ValidationPublication do
  let(:season) { create(:season, year: 2026) }
  let(:team) { create(:team, school: 'Sample School') }
  let(:batch) { legacy_departure_batch(season) }

  before do
    create(:team_season, season:, team:)
    capture_departures(batch)
    save_departure_rows(batch, departure_rows(team))
  end

  def prepare(record = batch)
    operation = Departures::ValidationPreparation.create(record)
    PrepareDepartureValidationJob.perform_now(operation.id)
    operation.reload
  end

  def old_publication
    review = Departures::BatchReview.new(batch)
    review.publish({ 'confirm' => '1', 'review_key' => review.review_key }, reviewer: 'historical@example.com')
  end

  it 'retains current published progress and retries the same approved publication without moving later pointers' do
    operation = prepare
    approval = Departures::ValidationApproval.new(operation).call(reviewer: 'admin@example.com')
    revision = described_class.new(approval).call
    expect(operation.reload).to be_current
    expect(DepartureProgress.new(season).call.status).to eq('complete')
    expect(Departures::PersistedPayload.new(revision.id).digest).to eq(revision.reload.input_hash)
    correction = Departures::BatchSuccessor.new(batch).correct('Correct retained choices')
    second = prepare(correction)
    second_approval = Departures::ValidationApproval.new(second).call(reviewer: 'admin@example.com')
    later = described_class.new(second_approval).call
    expect(described_class.new(approval).call.id).to eq(revision.id)
    expect(TeamOffseasonProfile.pluck(:departure_revision_id)).to eq([later.id])
  end

  it 'validates an intact old publication without creating approval, revision or rewriting frozen evidence' do
    revision = old_publication
    original = revision.attributes
    operation = prepare(batch.reload)
    expect(operation.status).to eq('ready'), operation.error
    expect(operation.choices.fetch('historical_revision_id')).to eq(revision.id)
    expect(DepartureProgress.new(season).call.status).to eq('complete')
    expect(revision.reload.attributes).to eq(original)
    expect(DepartureApproval.count).to eq(0)
  end

  it 'rejects an unchanged-hash numeric representation edit of an old revision and keeps the download' do
    revision = old_publication
    payload = revision.payload.deep_dup
    payload.fetch('dataset').fetch('production').first.fetch('players').first['player_points'] = 500.0
    expect(Departures::Contract.digest(payload)).not_to eq(revision.input_hash)
    overwrite_departure_record(revision, payload:)
    operation = prepare(batch.reload)
    expect(operation.status).to eq('failed')
    expect(operation.error).to match(/published.*(payload|hash)/i)
    expect(DepartureProgress.new(season).call.status).to eq('needs_review')
    expect(OffseasonInputRevision.count).to eq(1)
  end

  it 'rejects representational corruption of a saved legacy dataset even when JSONB equality would accept it' do
    attempt = batch.attempt
    data = attempt.dataset.deep_dup
    data.fetch('production').first.fetch('players').first['player_points'] = 500.0
    overwrite_departure_record(attempt, dataset: data)
    operation = prepare
    expect(operation.status).to eq('failed')
    expect(operation.error).to include('differs from replay')
  end

  it 'records unexpected preparation failure and publication rollback visibly, allowing the exact approval to retry' do
    allow(Departures::ValidationEvidence).to receive(:new).and_raise(RuntimeError, 'Interrupted parser')
    operation = prepare
    expect(operation).to have_attributes(status: 'failed', error: 'Interrupted parser')
    allow(Departures::ValidationEvidence).to receive(:new).and_call_original
    operation = prepare
    approval = Departures::ValidationApproval.new(operation).call(reviewer: 'admin@example.com')
    publisher = described_class.new(approval)
    allow(described_class).to receive(:new).and_return(publisher)
    allow(publisher).to receive(:publish_batch).and_raise(RuntimeError,
                                                          'Interrupted after profile write')
    PublishDepartureValidationJob.perform_now(approval.id)
    expect(operation.reload).to have_attributes(status: 'publish_failed', error: 'Interrupted after profile write')
    expect([OffseasonInputRevision.count, TeamOffseasonProfile.count, batch.reload.status]).to eq([0, 0, 'draft'])
    allow(publisher).to receive(:publish_batch).and_call_original
    PublishDepartureValidationJob.perform_now(approval.id)
    expect(operation.reload.status).to eq('published')
    expect([DepartureApproval.count, OffseasonInputRevision.count]).to eq([1, 1])
  end

  it 'retains GoodJob interruption states and retries publication with the same immutable approval' do
    operation = Departures::ValidationPreparation.create(batch)
    PrepareDepartureValidationJob.new(operation.id).rescue_with_handler(GoodJob::InterruptError.new('Stopped worker'))
    expect(operation.reload.status).to eq('failed')
    operation = prepare
    approval = Departures::ValidationApproval.new(operation).call(reviewer: 'admin@example.com')
    PublishDepartureValidationJob.new(approval.id).rescue_with_handler(GoodJob::InterruptError.new('Stopped publication'))
    expect(operation.reload.status).to eq('publish_failed')
    expect([OffseasonInputRevision.count, TeamOffseasonProfile.count]).to eq([0, 0])
    PublishDepartureValidationJob.perform_now(approval.id)
    expect(operation.reload.status).to eq('published')
    expect(DepartureApproval.count).to eq(1)
  end

  it 'rejects SQL reparenting of sealed proposals and dataset rows to an unsealed owner', :aggregate_failures do
    candidate = Departures::ValidationPreparation.create(batch)
    candidate.update!(status: 'running')
    operation = prepare
    proposal = operation.proposals.first
    replacement = DepartureDatasetNormalization.create!(identity: SecureRandom.uuid, status: 'running', header: {})
    row = DepartureDatasetRow.where(departure_dataset_normalization_id: operation.departure_dataset_normalization_id).first
    [[proposal, { departure_validation_id: candidate.id }],
     [row, { departure_dataset_normalization_id: replacement.id }]].each do |record, changes|
      expect do
        ApplicationRecord.transaction(requires_new: true) { overwrite_departure_record(record, changes) }
      end.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    end
    expect(operation.reload).to be_current
    expect(operation.proposals.pluck(:id)).to eq([proposal.id])
    expect(row.reload.departure_dataset_normalization_id).to eq(operation.departure_dataset_normalization_id)
  end

  it 'rejects a proposal move after profile validation and rolls back every publication output', :aggregate_failures do
    candidate = Departures::ValidationPreparation.create(batch)
    candidate.update!(status: 'running')
    operation = prepare
    approval = Departures::ValidationApproval.new(operation).call(reviewer: 'admin@example.com')
    profiles = Departures::ProfilePublication.new(operation, season)
    allow(Departures::ProfilePublication).to receive(:new).and_return(profiles)
    allow(profiles).to receive(:validate).and_wrap_original do |method|
      method.call
      ApplicationRecord.transaction(requires_new: true) do
        overwrite_departure_record(operation.proposals.first, departure_validation_id: candidate.id)
      end
    end
    expect do
      ApplicationRecord.transaction(requires_new: true) { described_class.new(approval).call }
    end.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    expect([OffseasonInputRevision.count, TeamOffseasonProfile.count, batch.reload.status]).to eq([0, 0, 'draft'])
    expect(operation.reload).to be_current
    expect(operation.proposals.count).to eq(1)
  end

  it 'rejects SQL retargeting or validator replacement even before a queued operation starts' do
    operation = Departures::ValidationPreparation.create(batch)
    successor = capture_departures(batch)
    [{ departure_acquisition_id: successor.id }, { validator_version: 'untrusted-version' }].each do |changes|
      ApplicationRecord.transaction(requires_new: true) do
        expect { overwrite_departure_record(operation, changes) }.to raise_error(ActiveRecord::StatementInvalid, /identity is immutable/)
        raise ActiveRecord::Rollback
      end
    end
    expect(operation.reload).to have_attributes(status: 'queued', generation: nil)
  end
end
