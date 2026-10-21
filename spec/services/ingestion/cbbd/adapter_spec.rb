# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe Ingestion::Cbbd::Adapter do
  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/ingestion/cbbd/final.json').read) }
  let(:directory) { Dir.mktmpdir('cbbd') }
  let(:responses) { [fixture['games'], fixture['boxes']] }
  let(:transport) { ->(_uri, _key) { { status: 200, headers: {}, body: responses.shift.to_json } } }
  let(:options) do
    { season: 2026, start_date: '2025-11-01', end_date: '2025-11-01', capture_directory: directory,
      api_key: 'sentinel-private-key', transport: transport, sleeper: ->(_seconds) {} }
  end

  after { FileUtils.remove_entry(directory) }

  def run_adapter
    described_class.new(**options).call
  end

  it 'acquires and replays only game endpoints within the original two-request budget' do
    requests = []
    recording_transport = lambda do |uri, _key|
      requests << uri.path
      payload = { '/games' => fixture['games'], '/games/teams' => fixture['boxes'] }.fetch(uri.path)
      { status: 200, headers: {}, body: payload.to_json }
    end
    result = described_class.new(**options, transport: recording_transport, max_requests: 2).call
    expect(result['acquisition']).to include('complete' => true, 'attempts' => 2)
    expect(result['acquisition']['partitions'].pluck('endpoint')).to eq(%w[/games /games/teams])
    expect(requests).to eq(%w[/games /games/teams])
    allow(Ingestion::Cbbd::Client).to receive(:new).and_raise('Replay must remain offline')
    expect(described_class.replay(manifest: result['manifest'])).to eq(result)
  end

  it 'retains an unmapped valid final with official totals' do
    observation = run_adapter.fetch('observations').sole
    expect(observation).to include('format' => 'ingestion-v1', 'semantic_profile' => 'official-team-totals-v1',
                                   'source_completed' => true, 'numeric_valid' => true, 'model_eligible' => false)
    expect(observation['home']['stats']['minutes']['value']).to eq(200)
    expect(observation['home']['stats']['turnovers']['value']).to eq(10)
    expect(observation['venue']['certainty']).to eq('unknown')
  end

  it 'never writes domain games or invokes the importer' do
    allow(Importer::GamesImporter).to receive(:import)
    counts = [Game.count, TeamGame.count]
    run_adapter
    expect([Game.count, TeamGame.count]).to eq(counts)
    expect(Importer::GamesImporter).not_to have_received(:import)
  end

  it 'replays immutable private provenance without secrets' do
    result = run_adapter
    expect(result['acquisition']['complete']).to be(true)
    expect(described_class.replay(manifest: result['manifest'])).to eq(result)
    expect(Dir.glob("#{directory}/*").map { |path| File.read(path) }.join).not_to include('sentinel-private-key')
  end

  it 'requires explicit valid bounded dates and ending season before HTTP' do
    allow(transport).to receive(:call)
    expect { described_class.new(**options, start_date: '2025-2-1') }.to raise_error(ArgumentError)
    expect { described_class.new(**options, season: 'bad') }.to raise_error(ArgumentError)
    expect { described_class.new(**options, end_date: '2025-10-31') }.to raise_error(ArgumentError)
    expect(transport).not_to have_received(:call)
  end

  it 'retains missing null blank and observed zero separately' do
    stats = fixture['boxes'][0]['teamStats']
    stats.delete('assists')
    stats['blocks'] = nil
    stats['steals'] = ' '
    stats['turnovers']['total'] = 0
    fields = run_adapter['observations'].sole['home']['stats']
    expect(fields['assists']['reason']).to eq('absent')
    expect(fields['blocks']['reason']).to eq('source_null')
    expect(fields['steals']['reason']).to eq('blank')
    expect(fields['turnovers']['value']).to eq(0)
  end

  it 'rejects mirrored opponent disagreements with both authoritative sources retained' do
    fixture['boxes'][0]['opponentStats']['assists'] = 99
    observation = run_adapter['observations'].sole
    expect(observation['numeric_valid']).to be(false)
    expect(observation['reasons'].join).to include('mirror')
    expect(observation['provenance'].size).to eq(3)
  end

  it 'never confirms nonfinal zero scores or a tied final' do
    fixture['games'][0].merge!('status' => 'scheduled', 'homePoints' => 0, 'awayPoints' => 0, 'startTimeTbd' => true)
    observation = run_adapter['observations'].sole
    expect(observation['source_completed']).to be(false)
    expect(observation['home']['score']['value']).to be_nil
    expect(observation['start_time']).to be_nil
    expect(observation['schedule_date']).to eq('2025-11-01')
  end

  it 'rejects replay tampering' do
    result = run_adapter
    File.write(Dir.glob("#{directory}/*.body").first, '[]')
    expect { described_class.replay(manifest: result['manifest']) }.to raise_error(Ingestion::Cbbd::CaptureStore::IntegrityError)
  end

  it 'keeps the original selected evidence when a later run captures a source correction' do
    original = run_adapter
    fixture['games'].first.merge!('homePoints' => 66, 'homePeriodPoints' => [30, 36])
    fixture['boxes'].first['teamStats']['freeThrows']['made'] = 11
    fixture['boxes'].first['teamStats']['points']['total'] = 66
    fixture['boxes'].last['opponentStats'] = fixture['boxes'].first['teamStats'].deep_dup
    responses.push(fixture['games'], fixture['boxes'])
    correction = run_adapter
    expect(correction['observations'].sole['numeric_valid']).to be(true)
    expect(correction['observations'].sole.dig('home', 'score', 'value')).to eq(66)
    expect(described_class.replay(manifest: original['manifest'])).to eq(original)
  end
end
