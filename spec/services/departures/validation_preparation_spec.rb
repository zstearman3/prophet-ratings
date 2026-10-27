# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::ValidationPreparation do
  let(:season) { create(:season, year: 2026) }
  let(:team) { create(:team, school: 'Sample School') }
  let(:other) { create(:team, school: 'Other School') }
  let(:batch) { legacy_departure_batch(season) }

  before do
    create(:team_season, season:, team:)
    create(:team_season, season:, team: other)
    capture_departures(batch)
    save_departure_rows(batch, departure_rows(team))
  end

  def prepared
    operation = described_class.create(batch)
    described_class.new(operation).call
    expect(operation.reload.status).to eq('ready'), operation.error
    operation
  end

  it 'publishes exactly the authenticated original payload and links all target profiles atomically', :aggregate_failures do
    operation = prepared
    approval = Departures::ValidationApproval.new(operation).call(reviewer: 'admin@example.com')
    expected = Departures::RetainedEvidence.new(batch.attempt).bundle(approval.document, season)
    revision = Departures::ValidationPublication.new(approval).call
    expect(revision.reload).to have_attributes(payload: expected, input_hash: Departures::Contract.digest(expected))
    expect(revision.team_input(team.id)['loss_share']).to eq(0.25)
    expect(revision.team_input(other.id)['loss_share']).to eq(0.0)
    expect(TeamOffseasonProfile.distinct.pluck(:departure_revision_id)).to eq([revision.id])
    expect(batch.reload.revision_id).to eq(revision.id)
    expect(Departures::ValidationPublication.new(approval).call.id).to eq(revision.id)
  end

  it 'rejects actual raw corruption with unchanged timestamps before writing any inputs' do
    operation = prepared
    approval = Departures::ValidationApproval.new(operation).call(reviewer: 'admin@example.com')
    attempt = batch.attempt
    evidence = attempt.evidence.deep_dup
    evidence.values.first['snapshot_base64'] = Base64.strict_encode64('corrupt')
    overwrite_departure_record(attempt, evidence:)
    expect { Departures::ValidationPublication.new(approval).call }.to raise_error(ArgumentError, /hash mismatch|changed/)
    expect(operation.reload.status).to eq('stale')
    expect([OffseasonInputRevision.count, TeamOffseasonProfile.count]).to eq([0, 0])
  end

  it 'rejects forged report, proposal, and approval documents even with recomputed caller hashes' do
    operation = prepared
    approval = Departures::ValidationApproval.new(operation).call(reviewer: 'admin@example.com')
    document = approval.document.merge('reviewed_by' => 'forged')
    overwrite_departure_record(approval, document:, review_hash: Departures::Contract.digest(document))
    expect { Departures::ValidationPublication.new(approval.reload).call }.to raise_error(ArgumentError, /approval|certificate/i)
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'rejects an inserted dependency after approval and keeps missing production unknown' do
    operation = prepared
    approval = Departures::ValidationApproval.new(operation).call(reviewer: 'admin@example.com')
    TeamAlias.create!(team:, source: 'school.example', value: 'New alias')
    expect(operation.reload).not_to be_current
    expect { Departures::ValidationPublication.new(approval).call }.to raise_error(ArgumentError, /changed/)
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'keeps incomplete selection accounting unknown instead of certifying zero' do
    batch.update!(decisions: batch.decisions.reject { |row| row['selection_key'] == '2025/1' })
    operation = prepared
    expect(operation.report.fetch('teams').pluck('loss_share')).to eq([nil, nil])
    expect(operation.report.fetch('gaps')).to include('Selection 2025/1: unknown_participation')
    expect { Departures::ValidationApproval.new(operation).call(reviewer: 'admin') }.to raise_error(ArgumentError, /Acknowledge/)
  end

  it 'rejects coordinated invalid manifests and saved facts despite matching caller digests' do
    attempt = batch.attempt
    manifest = attempt.manifest.merge('expected_picks' => [])
    dataset = attempt.dataset.merge('expected_picks' => [])
    dataset['dataset_revision'] = Departures::Contract.digest(dataset.except('dataset_revision'))
    overwrite_departure_record(attempt, manifest:, dataset:)
    operation = described_class.create(batch)
    described_class.new(operation).call
    expect(operation.reload.status).to eq('failed')
    expect(operation.proposals).to be_empty
  end

  it 'rejects dependency changes before the final seal rather than signing mixed input identities' do
    operation = described_class.create(batch)
    allow(Departures::PreparedProposal).to receive(:new).and_wrap_original do |constructor, *args|
      TeamAlias.create!(team:, source: 'unused.example', value: 'Concurrent identity change')
      constructor.call(*args)
    end
    described_class.new(operation).call
    expect(operation.reload.status).to eq('failed')
    expect(operation.error).to include('changed during preparation')
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'rejects proposal replacement between the coherent snapshot and the final locked seal' do
    operation = described_class.create(batch)
    preparer = described_class.new(operation)
    allow(preparer).to receive(:seal).and_wrap_original do |method, proof|
      proposal = operation.proposals.first!
      overwrite_departure_record(proposal, input: proposal.input.merge('loss_share' => 0.0))
      method.call(proof)
    end
    preparer.call
    expect(operation.reload.status).to eq('failed')
    expect(operation.certificate).to be_blank
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'safely resumes an interrupted running operation with a committed partial projection', :aggregate_failures do
    operation = described_class.create(batch)
    interrupted = described_class.new(operation)
    allow(interrupted).to receive(:seal).and_raise(Interrupt, 'synthetic worker stop')
    expect { interrupted.call }.to raise_error(Interrupt)
    expect(operation.reload.status).to eq('running')
    expect(operation.proposals.count).to eq(2)
    described_class.new(operation).call
    expect(operation.reload.status).to eq('ready'), operation.error
    expect(operation.proposals.count).to eq(2)
    expect(operation).to be_current
  end

  it 'rejects an older operation when a newer acquisition exists before it starts' do
    operation = described_class.create(batch)
    capture_departures(batch)
    described_class.new(operation).call
    expect(operation.reload.status).to eq('failed')
    expect(operation.error).to include('Preparation changed')
    expect(operation.proposals).to be_empty
  end

  it 'keeps legacy replay and file bundle APIs usable after a pending successor is validated' do
    attempt = capture_departures(batch)
    expected = attempt.dataset
    overwrite_departure_record(attempt, dataset: { 'storage_version' => 'departure-validation-pending-v1' })
    operation = prepared
    expect(attempt.reload.dataset).to eq(expected)
    expect(Departures::RetainedEvidence.new(attempt).verified_dataset(batch.plan)).to eq(expected)
    approval = Departures::ValidationApproval.new(operation).call(reviewer: 'admin')
    payload = Departures::RetainedEvidence.new(attempt).bundle(approval.document, season)
    expect(payload.fetch('dataset')).to eq(expected)
  end

  context 'with a coherent source snapshot' do
    it 'does not enroll retained raw capture bodies in the outer preparation transaction' do
      source = {
        'id' => 'school', 'type' => 'sidearm_totals', 'url' => 'https://school.example/stats/2024-25',
        'snapshot_kind' => 'raw_html', 'snapshot_location' => 'source.html', 'team_name_source' => 'Sample School',
        'scope' => Departures::Contract::SCOPE, 'scope_evidence' => 'Verified final overall scope',
        'http_status' => 200, 'captured_at' => '2025-06-30T00:00:00Z', 'observed_at' => '2025-06-30T00:00:00Z',
        'source_as_of_reason' => 'Publication timestamp not established'
      }
      bytes = Rails.root.join('spec/fixtures/departures/school.html').binread
      source['snapshot_sha256'] = Digest::SHA256.hexdigest(bytes)
      source['snapshot_location'] = "#{source['snapshot_sha256']}.html"
      ApplicationRecord.transaction(requires_new: true) do
        record = Departures::SourceNormalizer.new(source, bytes, { 'prior_season_year' => 2025 }, identity: SecureRandom.uuid).call
        expect(record.status).to eq('completed')
        records = Array(ApplicationRecord.connection.current_transaction.records)
        expect(records.grep(DepartureSourceCapture)).to be_empty
      end
    end
  end
end
