# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::CbbdAcquisition do
  let(:directory) { Dir.mktmpdir('departure-cbbd') }
  let(:plan) do
    { 'provider' => 'cbbd', 'schema' => 'draft-departures-v2', 'extraction_version' => 'cbbd-draft-season-totals-v1',
      'draft_year' => 2025, 'prior_season_year' => 2025, 'target_year' => 2026, 'expected_picks' => [1, 59],
      'scope_evidence' => 'Reviewed final scope', 'max_requests' => 5, 'retries' => 1 }
  end
  let(:checkpoints) { [] }
  let(:transport) { ->(_uri, _key) { { status: 429, body: 'quota synthetic-key', headers: {} } } }

  after { FileUtils.remove_entry(directory) }

  def acquire
    described_class.new(plan:, directory:, api_key: 'synthetic-key', transport:, sleeper: ->(_) {},
                        checkpoint: ->(manifest) { checkpoints << manifest.deep_dup }).call
  end

  it 'shares one finite budget across sources and retries and retains each failed response before continuing' do
    manifest = acquire
    expect(manifest.fetch('captures').size).to eq(5)
    expect(manifest.fetch('sources').pluck('failure')).to all(be_present)
    expect(checkpoints.map { |entry| entry.fetch('captures').size }).to include(1, 2, 3, 4, 5)
    expect(JSON.generate(manifest)).not_to include('synthetic-key')
    expect(File.binread(File.join(directory, manifest.fetch('captures').first['snapshot_location']))).to eq('quota [REDACTED]')
  end

  it 'retains earlier bytes when execution is interrupted and does not label remaining sources complete' do
    count = 0
    allow(transport).to receive(:call) do
      count += 1
      raise Interrupt if count == 2

      { status: 200, body: '[]', headers: {} }
    end
    expect { acquire }.to raise_error(Interrupt)
    expect(checkpoints.last.fetch('captures').size).to eq(1)
    expect(checkpoints.last.fetch('sources').drop(1).pluck('failure')).to all(be_present)
  end

  it 'fails a missing key before any network request or capture' do
    expect do
      described_class.new(plan:, directory:, api_key: '', transport:).call
    end.to raise_error(ArgumentError, /CBBD_API_KEY/)
    expect(Dir.children(directory)).to be_empty
  end
end
