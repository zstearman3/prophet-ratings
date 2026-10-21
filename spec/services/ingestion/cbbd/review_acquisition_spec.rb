# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::Cbbd::ReviewAcquisition do
  let(:season) { create(:season, year: 2026) }
  let(:run) { CbbdReviewRun.create!(season:, start_date: '2025-11-01', end_date: '2025-11-02', maximum_requests: 4, retries: 0) }
  let(:transport) { ->(*) { { status: 200, body: '[]', headers: {} } } }

  it 'starts queued with durable conservative bounds and an unknown-coverage manifest' do
    expect(run.manifest).to include('finalized' => false, 'bounds' => run.bounds, 'maximum_requests' => 4, 'retries' => 0)
    expect(run.manifest['acquisition']).to include('complete' => false, 'attempts' => 0, 'coverage' => 'unknown')
  end

  it 'retains verified private evidence and normalized empty coverage without identity or domain writes' do
    described_class.new(run, api_key: 'synthetic', transport:).call
    expect(run.reload.status).to eq('completed')
    expect(run.captures.count).to eq(2)
    expect(run.verified_replay.fetch('observations')).to eq([])
    expect(run.manifest.dig('acquisition', 'attempts')).to eq(2)
    expect([TeamExternalIdentity.count, GameExternalIdentity.count, IdentityMappingDecision.count]).to eq([0, 0, 0])
  end

  it 'retains failed request evidence and never upgrades incomplete acquisition' do
    described_class.new(run, api_key: 'synthetic', transport: ->(*) { { status: 401, body: 'secret synthetic', headers: {} } }).call
    expect(run.reload.status).to eq('failed')
    expect(run.verified_replay['complete']).to be(false)
    expect(run.captures.count).to eq(2)
  end

  it 'fails missing configuration without requests and does not expose secrets' do
    allow(transport).to receive(:call)
    described_class.new(run, api_key: '', transport:).call
    expect(run.reload.status).to eq('failed')
    expect(run.failure).to include('CBBD_API_KEY is required on the worker')
    expect(transport).not_to have_received(:call)
    expect(run.captures).to be_empty
  end

  it 'marks an interrupted running run failed without renewing its budget' do
    run.update!(status: 'running')
    allow(transport).to receive(:call)
    described_class.new(run, api_key: 'synthetic', transport:).call
    expect(run.reload.failure).to include('interrupted')
    expect(transport).not_to have_received(:call)
    expect { run.verified_replay }.to raise_error(ArgumentError, /finalized/)
  end

  it 'fails closed when retained bytes change' do
    described_class.new(run, api_key: 'synthetic', transport:).call
    capture = run.captures.first
    CbbdReviewCapture.connection.execute("UPDATE cbbd_review_captures SET body = 'corrupt' WHERE id = #{Integer(capture.id)}")
    expect { run.verified_replay }.to raise_error(Ingestion::Cbbd::CaptureStore::IntegrityError)
  end

  [3000, 1].each do |row_cap|
    it "retains conservative unknown coverage when interrupted with row cap #{row_cap}" do
      fixture = JSON.parse(Rails.root.join('spec/fixtures/ingestion/cbbd/final.json').read)
      attempts = 0
      interrupted = lambda do |*|
        attempts += 1
        raise IOError, 'synthetic interruption' if attempts > 1

        { status: 200, body: fixture['games'].to_json, headers: {} }
      end
      # Terminate outside Client's bounded transport handling, as a killed worker would.
      allow(Ingestion::Cbbd::Response).to receive(:new).and_wrap_original do |original, *arguments|
        raise Interrupt, 'synthetic worker termination' if attempts > 1

        original.call(*arguments)
      end
      expect { described_class.new(run, api_key: 'private-key', transport: interrupted, row_cap:).call }.to raise_error(Interrupt)
      expect(run.reload.manifest).to include('finalized' => false)
      expect(run.manifest['acquisition']).to include('complete' => false, 'attempts' => 1, 'selected_captures' => [])
      described_class.new(run, api_key: 'private-key', transport: interrupted).call
      expect(run.reload.failure).to include('interrupted')
      expect { Ingestion::Reconciliation::RunReview.new(run).compare }.to raise_error(ArgumentError, /finalized/)
    end
  end

  it 'checkpoints the original complete acquisition ledger before normalization can fail' do
    normalizer = instance_double(Ingestion::Cbbd::RunNormalizer)
    allow(Ingestion::Cbbd::RunNormalizer).to receive(:new).and_return(normalizer)
    allow(normalizer).to receive(:call).and_raise(ArgumentError, 'private-key')
    described_class.new(run, api_key: 'private-key', transport:).call
    expect(run.reload.manifest).to include('finalized' => true)
    expect(run.manifest['acquisition']).to include('attempts' => 2, 'complete' => true)
    expect(run.failure).not_to include('private-key')
    expect { run.verified_replay }.to raise_error(ArgumentError, /normalized/)
  end
end
