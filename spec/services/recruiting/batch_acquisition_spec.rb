# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recruiting::BatchAcquisition do
  let(:season) { create(:season, year: 2027) }
  let!(:team) { create(:team, school: 'Duke') }
  let(:batch) do
    RecruitingBatch.create!(season:, source_year: 2026,
                            extract_bytes: JSON.generate('provider' => 'cbbd', 'extraction_version' => Recruiting::CbbdExtract::VERSION))
  end
  let(:body) { '[{"teamId":72,"team":"Duke","year":2026,"ranking":1,"rating":69.16}]' }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('CBBD_API_KEY', '').and_return('test-key')
    allow(Ingestion::Cbbd::HttpTransport).to receive(:call).and_return(status: 200, body:, headers: {})
    allow(HTTParty).to receive(:get).and_raise('Live 247 must never be requested')
  end

  it 'saves CBBD captures and normalized rows through the job and makes terminal retries no-ops' do
    AcquireRecruitingBatchJob.perform_now(batch.id)
    expect(batch.reload).to have_attributes(status: 'ready', page_count: 1, source_status: 'ok', next_url: nil)
    expect(batch.entries.sole).to have_attributes(team_id: team.id, class_points: BigDecimal('69.16'), average_rating: nil)
    original = [batch.attributes, batch.entries.map(&:attributes)]
    AcquireRecruitingBatchJob.perform_now(batch.id)
    expect([batch.reload.attributes, batch.entries.map(&:attributes)]).to eq(original)
    expect(Ingestion::Cbbd::HttpTransport).to have_received(:call).once
    expect(HTTParty).not_to have_received(:get)
  end

  it 'preserves interrupted evidence and does not reinterpret legacy queued 247 batches', :aggregate_failures do
    batch.update!(status: 'fetching', snapshot_bytes: 'retained-capture')
    described_class.new(batch).call
    expect(batch.reload).to have_attributes(status: 'failed', snapshot_bytes: 'retained-capture')
    expect(batch.failure_message).to include('interrupted')
    legacy = RecruitingBatch.create!(season:, source_year: 2026)
    described_class.new(legacy).call
    expect(legacy.reload.status).to eq('failed')
    expect(legacy.source_label).to eq('247 Recruit Composite')
    expect(legacy.failure_message).to include('new CBBD batch')
    expect(Ingestion::Cbbd::HttpTransport).not_to have_received(:call)
  end

  it 'preserves CBBD provenance when runtime credentials are missing and retains authentication failures' do
    allow(ENV).to receive(:fetch).with('CBBD_API_KEY', '').and_return('')
    described_class.new(batch).call
    expect(batch.reload.status).to eq('failed')
    expect(batch.source_label).to include('CBBD')
    expect(batch.failure_message).to eq('CBBD_API_KEY is required')
    expect(Ingestion::Cbbd::HttpTransport).not_to have_received(:call)
  end

  it 'retains failed HTTP evidence instead of producing empty coverage' do
    allow(Ingestion::Cbbd::HttpTransport).to receive(:call).and_return(status: 401, body: 'Denied', headers: {})
    described_class.new(batch).call
    expect(batch.reload).to have_attributes(status: 'failed', source_status: 'authentication')
    expect(batch.snapshot_bytes).to include(Base64.strict_encode64('Denied'))
    expect(batch.entries).to be_empty
    expect { Recruiting::BatchReview.new(batch).publish({ 'confirm' => '1' }, reviewer: 'reviewer') }
      .to raise_error(ArgumentError, /unpublished/)
  end

  it 'preserves the original acquisition exception when recording the failure also fails' do
    error = IOError.new('Source unavailable')
    allow(Recruiting::CbbdAcquisition).to receive(:new).and_raise(error)
    allow(batch).to receive(:update!).and_call_original
    allow(batch).to receive(:update!).with(status: 'failed', failure_message: error.message)
                                     .and_raise(ActiveRecord::StatementInvalid, 'Database unavailable')
    expect { described_class.new(batch).call }.to(raise_error { |raised| expect(raised).to equal(error) })
    expect(batch.reload.status).to eq('fetching')
  end
end
