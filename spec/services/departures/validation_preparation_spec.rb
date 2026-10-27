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

  it 'authenticates complete retained evidence, preserves exact payload and publishes a first revision', :aggregate_failures do
    operation = described_class.create(batch)
    described_class.new(operation).call
    expect(operation.reload.status).to eq('ready'), operation.error
    approval = Departures::ValidationApproval.new(operation).call(reviewer: 'admin@example.com')
    expected = Departures::RetainedEvidence.new(batch.attempt).bundle(approval.document, season)
    revision = Departures::ValidationPublication.new(approval).call
    expect(revision.reload).to have_attributes(payload: expected, input_hash: Departures::Contract.digest(expected))
    persisted = OffseasonInputRevision.find(revision.id)
    expect(persisted.input_hash).to eq(Departures::Contract.digest(persisted.payload))
    expect([revision.team_input(team.id)['loss_share'], revision.team_input(other.id)['loss_share']]).to eq([0.25, 0.0])
    expect(TeamOffseasonProfile.distinct.pluck(:departure_revision_id)).to eq([revision.id])
    expect(Departures::ValidationPublication.new(approval).call.id).to eq(revision.id)
  end

  it 'publishes over existing recruiting and scalar profile evidence without replaying old revisions' do
    review = { 'review_status' => 'reviewed', 'approval' => { 'approved_by' => 'admin', 'approved_at' => Time.current.iso8601 } }
    payload = { 'kind' => 'recruiting', 'dataset_hash' => 'a' * 64, 'review_hash' => Departures::Contract.digest(review),
                'review' => review, 'team_inputs' => { team.id.to_s => {} } }
    recruiting = OffseasonInputRevision.create!(season:, kind: 'recruiting', version: 'existing-recruiting', reason: 'Approved by admin',
                                                payload:, input_hash: Departures::Contract.digest(payload),
                                                dataset_hash: payload.fetch('dataset_hash'), review_hash: payload.fetch('review_hash'))
    profile = TeamOffseasonProfile.create!(team_season: season.team_seasons.find_by!(team:), recruiting_revision: recruiting,
                                           recruiting_score: 25, returning_minutes_pct: 0.75, observed_on: '2025-06-30',
                                           source_reference: 'Synthetic retained reviewed evidence', input_units: TeamOffseasonProfile::INPUT_UNITS)
    operation = described_class.create(batch)
    described_class.new(operation).call
    approval = Departures::ValidationApproval.new(operation).call(reviewer: 'admin@example.com')
    revision = Departures::ValidationPublication.new(approval).call
    expect(profile.reload).to have_attributes(departure_revision_id: revision.id, recruiting_revision_id: recruiting.id,
                                              recruiting_score: 25, returning_minutes_pct: 0.75)
  end

  it 'fails visibly for unchanged-timestamp raw corruption without loading the annual evidence column' do
    operation = described_class.create(batch)
    attempt = batch.attempt
    evidence = attempt.evidence.deep_dup
    evidence.values.first['snapshot_base64'] = Base64.strict_encode64('corrupt')
    overwrite_departure_record(attempt, evidence:)
    described_class.new(operation).call
    expect(operation.reload.status).to eq('failed')
    expect(operation.error).to include('hash mismatch')
  end

  it 'authenticates an unreferenced source before projecting only the selected evidence' do
    attempt = batch.attempt
    source = attempt.manifest.fetch('sources').last.merge('id' => 'unused-source')
    manifest = attempt.manifest.merge('sources' => attempt.manifest.fetch('sources') + [source])
    evidence = attempt.evidence.merge('unused-source' => { 'snapshot_base64' => Base64.strict_encode64('corrupt unused source') })
    overwrite_departure_record(attempt, manifest:, evidence:)
    operation = described_class.create(batch)
    described_class.new(operation).call
    expect(operation.reload).to have_attributes(status: 'failed', generation: nil)
    expect(operation.error).to include('hash mismatch')
  end

  it 'keeps unreferenced failed sources as hard failures rather than dropping global coverage evidence' do
    attempt = batch.attempt
    failure = { 'id' => 'unused-failed-source', 'type' => 'sidearm_totals', 'url' => 'https://unused.example/stats', 'failure' => 'Retained fetch failure' }
    sources = attempt.manifest.fetch('sources') + [failure]
    dataset = attempt.dataset.merge('sources' => sources, 'failures' => [failure])
    dataset['dataset_revision'] = Departures::Contract.digest(dataset.except('dataset_revision'))
    overwrite_departure_record(attempt, manifest: attempt.manifest.merge('sources' => sources), dataset:)
    operation = described_class.create(batch)
    described_class.new(operation).call
    expect(operation.reload).to have_attributes(status: 'failed', generation: nil)
    expect(operation.error).to include('Resolve failed departure sources')
  end

  it 'rejects coordinated invalid original manifest and saved-dataset contracts despite matching supplied hashes' do
    attempt = batch.attempt
    original = attempt.manifest
    duplicate = original.fetch('sources').last.merge('id' => original.fetch('sources').first.fetch('id'))
    cases = [{ 'schema' => 'unsupported' }, { 'extraction_version' => 'unsupported' },
             { 'expected_picks' => [] }, { 'expected_picks' => [1, 1] },
             { 'sources' => [original.fetch('sources').first, duplicate] },
             { 'sources' => [original.fetch('sources').last] }]
    cases.each do |changes|
      manifest = original.merge(changes)
      dataset = attempt.dataset.merge(changes.except('schema', 'extraction_version'))
      dataset['dataset_revision'] = Departures::Contract.digest(dataset.except('dataset_revision'))
      overwrite_departure_record(attempt, manifest:, dataset:)
      operation = described_class.create(batch)
      described_class.new(operation).call
      expect(operation.reload).to have_attributes(status: 'failed', generation: nil)
    end
    expect([OffseasonInputRevision.count, TeamOffseasonProfile.count]).to eq([0, 0])
  end

  it 'never certifies verified zero when coordinated empty picks and missing draft evidence agree with a supplied hash' do
    attempt = batch.attempt
    sources = [attempt.manifest.fetch('sources').last]
    manifest = attempt.manifest.merge('sources' => sources, 'expected_picks' => [])
    dataset = attempt.dataset.merge('sources' => sources, 'expected_picks' => [], 'selections' => [])
    dataset['dataset_revision'] = Departures::Contract.digest(dataset.except('dataset_revision'))
    overwrite_departure_record(attempt, manifest:, dataset:)
    overwrite_departure_record(batch, decisions: [])
    operation = described_class.create(batch.reload)
    described_class.new(operation).call
    expect(operation.reload).to have_attributes(status: 'failed', generation: nil)
    expect(operation.proposals).to be_empty
  end

  it 'rejects a dataset for a different target season before certifying any team inputs' do
    wrong_season = create(:season, year: 2027)
    create(:team_season, season: wrong_season, team:)
    overwrite_departure_record(batch, season_id: wrong_season.id)
    operation = described_class.create(batch.reload)
    described_class.new(operation).call
    expect(operation.reload).to have_attributes(status: 'failed', generation: nil)
    expect(operation.error).to include('target season mismatch')
  end

  it 'rejects a dependency edit during validation instead of certifying mixed evidence' do
    operation = described_class.create(batch)
    allow(Departures::PreparedProposal).to receive(:new).and_wrap_original do |constructor, *arguments|
      TeamAlias.create!(team:, source: 'unused.example', value: 'Another name')
      constructor.call(*arguments)
    end
    described_class.new(operation).call
    expect(operation.reload.status).to eq('stale'), operation.error
  end

  it 'rejects SQL changes after approval and never applies part of an obsolete proposal' do
    operation = described_class.create(batch)
    described_class.new(operation).call
    approval = Departures::ValidationApproval.new(operation).call(reviewer: 'admin@example.com')
    overwrite_departure_record(team, school: 'Changed')
    expect { Departures::ValidationPublication.new(approval).call }.to raise_error(ArgumentError, /changed/)
    expect([OffseasonInputRevision.count, TeamOffseasonProfile.count]).to eq([0, 0])
  end

  it 'does not deserialize large annual metadata through mutable AR attributes while preparing or publishing' do
    attempt = batch.attempt
    manifest = attempt.manifest.deep_dup
    manifest.fetch('sources').last['archival_annotation'] = 'x' * (1024 * 1024)
    dataset = attempt.dataset.merge('sources' => manifest.fetch('sources'))
    dataset['dataset_revision'] = Departures::Contract.digest(dataset.except('dataset_revision'))
    overwrite_departure_record(attempt, manifest:, dataset:)
    annual_header_reads = 0
    trace = TracePoint.new(:call) do |point|
      next unless point.defined_class == ActiveRecord::Type::Json && point.method_id == :deserialize

      value = point.binding.local_variable_get(:value)
      annual_header_reads += 1 if value.is_a?(String) && value.bytesize > 1024 * 1024
    end
    operation = described_class.create(batch)
    revision = nil
    trace.enable do
      described_class.new(operation).call
      expect(operation.reload.status).to eq('ready'), operation.error
      approval = Departures::ValidationApproval.new(operation).call(reviewer: 'admin@example.com')
      revision = Departures::ValidationPublication.new(approval).call
    end
    expect(revision).to be_present
    expect(annual_header_reads).to eq(0)
  ensure
    trace&.disable
  end

  it 'invalidates a certificate when SQL changes a completed normalized source or annual header' do
    operation = described_class.create(batch)
    described_class.new(operation).call
    expect(operation.reload).to be_current
    source_id = operation.departure_dataset_normalization.source_normalization_ids.values.first
    overwrite_departure_record(DepartureSourceNormalization.find(source_id), rows_digest: 'a' * 64)
    expect(operation).not_to be_current
    next_operation = described_class.create(batch)
    described_class.new(next_operation).call
    expect(next_operation.reload).to be_current
    overwrite_departure_record(next_operation.departure_dataset_normalization, header: {})
    expect(next_operation).not_to be_current
  end

  it 'keeps proposal content write-once before sealing and rejects nonmember team proposals', :aggregate_failures do
    outsider = create(:team, school: 'Not a target member')
    operation = described_class.create(batch)
    preparer = described_class.new(operation)
    blocked = []
    allow(preparer).to receive(:seal).and_wrap_original do |method, prepared|
      proposal = operation.proposals.first
      mutations = [-> { overwrite_departure_record(proposal, input: {}) },
                   -> { overwrite_departure_record(proposal, team_id: outsider.id) },
                   -> { DepartureProposal.where(id: proposal.id).delete_all },
                   -> { operation.proposals.create!(team_id: outsider.id, input: {}) }]
      mutations.each do |mutation|
        ApplicationRecord.transaction(requires_new: true) do
          mutation.call
          raise ActiveRecord::Rollback
        end
      rescue ActiveRecord::StatementInvalid => error
        blocked << error.message
      end
      method.call(prepared)
    end
    preparer.call
    expect(blocked.length).to eq(4)
    expect(operation.reload.status).to eq('ready'), operation.error
    expect(operation).to be_current
    expect(operation.proposals.reload.order(:team_id).pluck(:team_id)).to eq([team.id, other.id].sort)
  end

  it 'rejects numeric-only changes to sealed report and review choices with exact stored content unchanged', :aggregate_failures do
    operation = described_class.create(batch)
    described_class.new(operation).call
    scope = DepartureValidation.where(id: operation.id)
    columns = [Arel.sql('report::text AS retained_report_text'), Arel.sql('choices::text AS retained_choices_text')]
    baseline = ApplicationRecord.uncached { scope.pick(*columns) }
    changes = { report: operation.report.deep_dup, choices: operation.choices.deep_dup }
    selection = changes.fetch(:report).fetch('selections').first
    selection['overall_pick'] = selection.fetch('overall_pick').to_f
    stint = changes.fetch(:choices).fetch('review').fetch('decisions').first.fetch('stints').first
    stint['team_id'] = stint.fetch('team_id').to_f
    changes.each do |column, value|
      expect(Departures::Contract.digest(value)).not_to eq(Departures::Contract.digest(operation.public_send(column)))
      expect do
        ApplicationRecord.transaction(requires_new: true) { overwrite_departure_record(operation, column => value) }
      end.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
      expect(ApplicationRecord.uncached { scope.pick(*columns) }).to eq(baseline)
    end
    expect(operation.reload).to be_current
    expect([DepartureApproval.count, OffseasonInputRevision.count]).to eq([0, 0])
  end

  it 'keeps sealed proposals and rows immutable even after a SQL status edit' do
    operation = described_class.create(batch)
    described_class.new(operation).call
    overwrite_departure_record(operation, status: 'running')
    proposal = operation.proposals.first
    row = operation.departure_dataset_normalization.rows.first
    [-> { overwrite_departure_record(proposal, input: {}) },
     -> { corrupt_departure_fact(row, {}) },
     -> { overwrite_departure_record(operation, report: {}) }].each do |tamper|
      ApplicationRecord.transaction(requires_new: true) do
        expect(&tamper).to raise_error(ActiveRecord::StatementInvalid, /immutable/)
        raise ActiveRecord::Rollback
      end
    end
  end
end
