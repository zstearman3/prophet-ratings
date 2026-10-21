# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::GameObservation do
  let(:payload) do
    { contract_version: 'ingestion-v1', semantic_profile: 'official-team-totals-v1', provider: 'synthetic',
      external_game_id: '001', season_year: 2025, schedule_date: '2025-01-01', source_status: 'scheduled',
      source_completed: false, captured_at: '2025-01-01T12:00:00Z', adapter_revision: 'test-1',
      home: { name: 'Home', stats: {} }, away: { name: 'Away', stats: {} } }
  end

  it 'rejects unsupported versions' do
    expect { described_class.new(payload.merge(contract_version: 'v99')).validate }.to raise_error(described_class::Invalid)
  end

  it 'preserves missing counts and observed zero' do
    observation = described_class.new(payload.deep_merge(home: { stats: { points: 0, minutes: '' } }))
    observation.validate
    expect(observation.data[:home][:stats]).to include(points: 0, minutes: nil)
    expect(observation.data[:home][:field_availability]).to include(points: 'observed', minutes: 'blank', turnovers: 'missing')
  end

  [true, 1.5, 'NaN', -1, 2_147_483_648].each do |invalid|
    it "rejects noninteger or unrepresentable count #{invalid.inspect}" do
      observation = described_class.new(payload.deep_merge(home: { stats: { points: invalid } }))
      expect { observation.validate }.to raise_error(described_class::Invalid)
    end
  end

  it 'rejects derived provider statistics' do
    observation = described_class.new(payload.deep_merge(home: { stats: { possessions: 70 } }))
    expect { observation.validate }.to raise_error(described_class::Invalid)
  end

  it 'rejects contradictory completion evidence' do
    expect { described_class.new(payload.merge(source_completed: true)).validate }.to raise_error(described_class::Invalid)
  end

  it 'rejects a known start on another Eastern date' do
    observation = described_class.new(payload.merge(start_time: '2025-01-01T01:00:00Z'))
    expect { observation.validate }.to raise_error(described_class::Invalid)
  end
end
