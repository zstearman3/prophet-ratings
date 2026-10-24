# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::RetainedEvidence do
  let(:season) { create(:season, year: 2026) }
  let(:batch) { legacy_departure_batch(season) }
  let(:attempt) { capture_departures(batch) }

  # Simulate corruption outside the immutable model API to verify the retained bytes remain authoritative.
  def overwrite_dataset(id, value)
    connection = DepartureAcquisition.connection
    connection.execute("UPDATE departure_acquisitions SET dataset = #{connection.quote(value.to_json)}::jsonb WHERE id = #{id.to_i}")
  end

  def overwrite_evidence(id, value)
    connection = DepartureAcquisition.connection
    connection.execute("UPDATE departure_acquisitions SET evidence = #{connection.quote(value.to_json)}::jsonb WHERE id = #{id.to_i}")
  end

  it 'compares the complete replay in PostgreSQL without reading the stored dataset into Ruby' do
    retained = attempt
    allow(retained).to receive(:dataset).and_call_original
    allow(retained).to receive(:evidence).and_call_original
    replay = described_class.new(retained, comparison: :persisted).verified_dataset(batch.plan)
    expect(replay.fetch('selections').size).to eq(60)
    expect(retained.accessed_fields).not_to include('dataset', 'evidence')
    expect(retained).not_to have_received(:dataset)
    expect(retained).not_to have_received(:evidence)
  end

  it 'rejects changed persisted data even when its stored revision hash has not changed' do
    retained = attempt
    overwrite_dataset(retained.id, retained.dataset.merge('target_year' => 2099))
    retained.reload
    allow(retained).to receive(:dataset).and_call_original
    expect { described_class.new(retained, comparison: :persisted).verified_dataset(batch.plan) }
      .to raise_error(ArgumentError, 'Retained departure dataset differs from replay')
    expect(retained).not_to have_received(:dataset)
  end

  it 'rejects empty persisted evidence before replay without materializing the stored dataset' do
    retained = attempt
    overwrite_dataset(retained.id, {})
    retained.reload
    allow(retained).to receive(:dataset).and_call_original
    expect { described_class.new(retained, comparison: :persisted).verified_dataset(batch.plan) }
      .to raise_error(ArgumentError, 'Acquire usable evidence before reviewing decisions')
    expect(retained).not_to have_received(:dataset)
  end

  it 'still compares in-memory mutations in the default editing and publication path' do
    attempt.dataset['target_year'] = 2099
    expect { described_class.new(attempt).verified_dataset(batch.plan) }
      .to raise_error(ArgumentError, 'Retained departure dataset differs from replay')
  end

  it 'still verifies source bytes before comparing the persisted replay' do
    retained = attempt
    changed = retained.evidence.deep_dup
    changed.fetch('source-1')['snapshot_base64'] = Base64.strict_encode64('changed source bytes')
    overwrite_evidence(retained.id, changed)
    retained.reload
    allow(retained).to receive(:dataset).and_call_original
    expect { described_class.new(retained, comparison: :persisted).verified_dataset(batch.plan) }
      .to raise_error(ArgumentError, 'Retained source hash mismatch')
    expect(retained).not_to have_received(:dataset)
  end

  it 'still verifies in-memory source-byte mutations in the default path' do
    attempt.evidence.fetch('source-1')['snapshot_base64'] = Base64.strict_encode64('changed source bytes')
    expect { described_class.new(attempt).verified_dataset(batch.plan) }
      .to raise_error(ArgumentError, 'Retained source hash mismatch')
  end

  it 'rejects unknown source identities before looking up their retained bytes' do
    retained = attempt.reload
    expect { described_class.new(retained, comparison: :persisted).bytes('unknown') }
      .to raise_error(ArgumentError, 'Unknown retained source')
  end

  it 'returns a review error when a persisted source body is missing' do
    retained = attempt
    overwrite_evidence(retained.id, {})
    retained.reload
    allow(retained).to receive(:evidence).and_call_original
    report = Departures::BatchReview.new(batch, comparison: :persisted).report(attempt: retained)
    expect(report.fetch('errors')).to include('Missing retained source bytes')
    expect(retained).not_to have_received(:evidence)
  end

  it 'preserves unsaved retained evidence comparison in the default path' do
    unsaved = attempt.dup
    replay = described_class.new(unsaved).verified_dataset(batch.plan)
    expect(replay).to eq(unsaved.dataset)
  end

  it 'returns readiness errors without loading stored selections after a persisted mismatch' do
    retained = attempt
    overwrite_dataset(retained.id, { 'tampered' => true })
    retained.reload
    allow(retained).to receive(:dataset).and_call_original
    report = Departures::BatchReview.new(batch, comparison: :persisted).report(attempt: retained)
    expect(report).to include('selections' => [], 'errors' => ['Retained departure dataset differs from replay'])
    expect(retained).not_to have_received(:dataset)
  end
end
