# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe Ingestion::Cbbd::BoundedRetriever do
  let(:directory) { Dir.mktmpdir('cbbd-bound') }
  let(:bounds) { Ingestion::Cbbd::Bounds.new(season: 2026, start_date: '2025-11-01', end_date: '2025-11-01') }
  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/ingestion/cbbd/final.json').read) }
  let(:responses) { [] }
  let(:transport) { ->(_uri, _key) { { status: 200, body: responses.shift.to_json, headers: {} } } }
  let(:adapter_options) do
    { season: 2026, start_date: '2025-11-01', end_date: '2025-11-01', capture_directory: directory,
      api_key: 'private-sentinel', transport: transport, sleeper: ->(_seconds) {}, row_cap: 3 }
  end

  after { FileUtils.remove_entry(directory) }

  it 'replays only successful leaves preserving saturated parents failed attempts and deduplication' do
    game = fixture['games'].first
    game['startDate'] = '2025-11-01T15:59:59.999Z'
    fixture['boxes'].each { |box| box['startDate'] = game['startDate'] }
    replies = [
      { status: 503, body: 'failure', headers: {} },
      { status: 200, body: [game, game, game].to_json, headers: {} },
      { status: 200, body: [game].to_json, headers: {} },
      { status: 200, body: [game].to_json, headers: {} },
      { status: 200, body: fixture['boxes'].to_json, headers: {} }
    ]
    options = adapter_options.merge(transport: ->(_uri, _key) { replies.shift })
    result = Ingestion::Cbbd::Adapter.new(**options).call
    ledger = result['acquisition']
    expect(ledger['selected_captures'].size).to eq(3)
    expect(ledger['captures'].size).to eq(5)
    expect(ledger['decisions'].sole['outcome']).to eq('identical')
    expect(Ingestion::Cbbd::Adapter.replay(manifest: result['manifest'])).to eq(result)
  end

  it 'marks conflicting duplicates incomplete and retains both evidence references' do
    game = fixture['games'].first
    responses.push([game, game.merge('homePoints' => 99)], [])
    result = Ingestion::Cbbd::Adapter.new(**adapter_options).call
    expect(result['complete']).to be(false)
    expect(result['acquisition']['failures'].pluck('reason')).to include('conflicting_duplicate')
    expect(Ingestion::Cbbd::Adapter.replay(manifest: result['manifest'])['acquisition']).to eq(result['acquisition'])
  end

  it 'never upgrades a saturated incomplete run on replay' do
    game = fixture['games'].first
    responses.concat(Array.new(6) { [game] })
    result = Ingestion::Cbbd::Adapter.new(**adapter_options, row_cap: 1, max_requests: 3).call
    expect(result['acquisition']).to include('complete' => false, 'attempts' => 3)
    expect(Ingestion::Cbbd::Adapter.replay(manifest: result['manifest'])).to eq(result)
  end

  it 'rejects out of window, wrong season and invalid identity rows' do
    rows = [fixture['games'].first.merge('id' => nil), fixture['games'].first.merge('id' => 2, 'season' => 2025),
            fixture['games'].first.merge('id' => 3, 'startDate' => '2025-11-03T12:00:00Z')]
    responses.push(rows, [])
    result = Ingestion::Cbbd::Adapter.new(**adapter_options, row_cap: 10).call
    expect(result['acquisition']['failures'].pluck('reason')).to contain_exactly('invalid_identity', 'season_mismatch', 'out_of_window')
  end

  it 'fails closed at a saturated one-second interval' do
    responses << fixture['games']
    store = Ingestion::Cbbd::CaptureStore.new(directory)
    client = Ingestion::Cbbd::Client.new(store: store, api_key: 'synthetic', transport: transport)
    retriever = described_class.new(client: client, bounds: bounds, row_cap: 1)
    retriever.send(:retrieve, '/games', bounds.start_time..(bounds.start_time + 1))
    expect(retriever.ledger['failures'].pluck('reason')).to eq(['saturated_minimum_interval'])
    expect(client.attempts).to eq(1)
  end

  it 'retains a failed child partition without claiming full coverage' do
    game = fixture['games'].first
    replies = [[game, game, game], [game], :failure, []]
    custom_transport = lambda do |_uri, _key|
      payload = replies.shift
      { status: payload == :failure ? 401 : 200, headers: {}, body: payload.to_json }
    end
    result = Ingestion::Cbbd::Adapter.new(**adapter_options, transport: custom_transport).call
    expect(result['acquisition']['complete']).to be(false)
    expect(result['acquisition']['failures'].pluck('reason')).to include('authentication')
    expect(Ingestion::Cbbd::Adapter.replay(manifest: result['manifest'])).to eq(result)
  end
end
