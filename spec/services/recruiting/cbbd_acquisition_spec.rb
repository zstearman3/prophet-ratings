# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recruiting::CbbdAcquisition do
  let(:season) { create(:season, year: 2026) }
  let(:batch) { RecruitingBatch.create!(season:, source_year: 2025, extract_bytes: JSON.generate('provider' => 'cbbd')) }
  let(:body) { Rails.root.join('spec/fixtures/recruiting/cbbd-2025.json').read }
  let(:transport) { ->(_uri, _key) { { status: 200, body:, headers: {} } } }

  def acquire(**)
    described_class.new(batch, api_key: 'test-key', transport:, sleeper: ->(_seconds) {}, **).call
    batch.reload
  end

  it 'captures the annual request, timestamps, hashes and exact response with truthful unknown auxiliary fields', :aggregate_failures do
    requests = []
    custom = lambda { |uri, _key|
      requests << uri.to_s
      { status: 200, body:, headers: {} }
    }
    acquire(transport: custom)
    expect(requests).to eq(['https://api.collegebasketballdata.com/recruiting/teams?year=2025'])
    expect(batch).to have_attributes(status: 'ready', source_status: 'ok', page_count: 1)
    expect(batch.dataset.extract.metadata).to include('provider' => 'cbbd', 'target_season' => 2026,
                                                      'source_as_of' => nil, 'snapshot_kind' => 'raw_json_bundle')
    expect(batch.dataset.manifest.fetch('rows').first.dig('values', 'average_rating')).to be_nil
    capture = JSON.parse(batch.snapshot_bytes).fetch('captures').sole
    expect(Base64.strict_decode64(capture.fetch('body_base64'))).to eq(body.b)
    expect(capture.fetch('sha256')).to eq(Digest::SHA256.hexdigest(body))
    expect(capture.dig('metadata', 'captured_at')).to be_present
  end

  it 'retains retries and fails a bounded quota outcome rather than treating failure as empty coverage' do
    response = ->(_uri, _key) { { status: 429, body: 'Quota exceeded', headers: { 'retry-after' => '0' } } }
    acquire(transport: response, max_requests: 2)
    expect(batch).to have_attributes(status: 'failed', source_status: 'request_budget', page_count: 2)
    expect(JSON.parse(batch.snapshot_bytes).fetch('captures').size).to eq(2)
    expect(batch.snapshot_bytes).to include(Base64.strict_encode64('Quota exceeded'))
  end

  it 'does not retry authentication failures and retains malformed or invalid source responses' do
    [{ status: 401, body: 'denied' }, { status: 200, body: '{broken' }, { status: 200, body: '{}' },
     { status: 200, body: '[{"teamId":"72","team":"Duke","year":2025,"rating":70}]' }].each do |response|
      acquire(transport: ->(_uri, _key) { response.merge(headers: {}) })
      expect(batch.status).to eq('failed')
      expect(JSON.parse(batch.snapshot_bytes).fetch('captures').size).to eq(1)
      expect(batch.dataset_revision).to be_nil
    end
  end

  it 'keeps a valid empty response distinct from failure and rejects altered retained response bytes' do
    acquire(transport: ->(_uri, _key) { { status: 200, body: '[]', headers: {} } })
    expect(batch.status).to eq('ready')
    expect(Recruiting::Preview.new(batch.dataset, season).call).to include('coverage' => 'empty', 'eligible_rows' => 0)
    captured = JSON.parse(batch.snapshot_bytes)
    captured['captures'].first['body_base64'] = Base64.strict_encode64('[{}]')
    batch.update!(snapshot_bytes: JSON.generate(captured))
    expect { batch.dataset }.to raise_error(ArgumentError, /hash changed/)
  end
end
