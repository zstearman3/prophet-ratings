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

  context 'with invalid source rows before valid rows and duplicates' do
    let(:game) { fixture['games'].first }
    let(:box) { fixture['boxes'].first }
    let(:invalid_games) do
      [game.merge('id' => nil), game.merge('season' => 2025),
       game.merge('startDate' => '2025-11-03T12:00:00Z'), game.merge('startDate' => 'malformed')]
    end
    let(:invalid_boxes) do
      [box.merge('teamId' => nil), box.merge('season' => 2025),
       box.merge('startDate' => '2025-11-03T12:00:00Z'), box.merge('startDate' => 'malformed')]
    end
    let(:result) { Ingestion::Cbbd::Adapter.new(**adapter_options, row_cap: 10).call }
    let(:ledger) { result['acquisition'] }

    before { responses.push(invalid_games + [game, game], invalid_boxes + fixture['boxes'] + [box]) }

    it 'excludes invalid games and boxes without shifting valid provenance indexes' do
      observation = result['observations'].sole
      expect(observation['numeric_valid']).to be(true)
      expect(observation['provenance'].pluck('row_index')).to eq([4, 4, 5])
      expect(result['orphan_boxes']).to be_empty
      expect(ledger['complete']).to be(false)
    end

    it 'retains each invalid raw row and its original capture index as acquisition failure evidence' do
      expect(ledger['failures'].pluck('reason')).to eq(%w[invalid_identity season_mismatch out_of_window unknown_source_time] * 2)
      ledger['captures'].each_with_index do |capture, index|
        failures = ledger['failures'].select { |failure| failure.dig('evidence', 'capture_id') == capture['id'] }
        expect(failures.map { |failure| failure.dig('evidence', 'row_index') }).to eq([0, 1, 2, 3])
        raw = JSON.parse(Ingestion::Cbbd::CaptureStore.new(directory).read(capture))
        expect(raw.first(4)).to eq([invalid_games, invalid_boxes][index])
      end
    end

    it 'replays the same filtered observations and original duplicate decisions without upgrading completeness' do
      expect(ledger['decisions'].pluck('outcome')).to eq(%w[identical identical])
      expect(ledger['decisions'].map { |decision| decision.dig('retained', 'row_index') }).to eq([4, 4])
      expect(ledger['decisions'].map { |decision| decision.dig('duplicate', 'row_index') }).to eq([5, 6])
      expect(Ingestion::Cbbd::Adapter.replay(manifest: result['manifest'])).to eq(result)
    end
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
