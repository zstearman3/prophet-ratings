# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::GameSyncProvider do
  let(:date) { Date.new(2026, 3, 8) }
  let(:season) { create(:season, year: 2026, start_date: date - 10, end_date: date + 10) }
  let(:options) { { api_key: 'synthetic', max_requests: 2, retries: 0, capture_directory: '/tmp/synthetic' } }
  let(:adapter) { instance_double(Ingestion::Cbbd::Adapter, call: acquisition) }
  let(:acquisition) { { 'complete' => true, 'observations' => [], 'acquisition' => { 'complete' => true, 'attempts' => 2 } } }

  before { allow(Ingestion::Cbbd::Adapter).to receive(:new).and_return(adapter) }

  it 'prepares one range and reports valid empties for its requested dates' do
    run = described_class.new(season:, dates: [date, date + 2], provider: 'cbbd', options:)
    expect(run.call(date)).to include(complete: true, valid_empty: true, imported_rows: 0)
    expect(run.call(date + 2)).to include(complete: true)
    expect(adapter).to have_received(:call).once
    expect(Ingestion::Cbbd::Adapter).to have_received(:new).with(season: 2026, start_date: date, end_date: date + 2, **options)
  end

  it 'does not acquire an empty resume window' do
    run = described_class.new(season:, dates: [], provider: 'cbbd', options:)
    expect(run.summary).to include(attempts: 0)
    expect(adapter).not_to have_received(:call)
  end

  it 'rejects unconfigured policy and unsupported providers before acquisition' do
    expect { described_class.new(season:, dates: [date], provider: 'other') }.to raise_error(ArgumentError)
    expect { described_class.new(season:, dates: [date], provider: 'cbbd') }.to raise_error(ArgumentError)
    expect { described_class.new(season:, dates: [date], provider: 'cbbd', options: options.merge(retries: 0.5)) }
      .to raise_error(ArgumentError)
    expect(adapter).not_to have_received(:call)
  end

  it 'holds incomplete acquisition across repeated date attempts without renewing its budget' do
    acquisition['complete'] = false
    run = described_class.new(season:, dates: [date], provider: 'cbbd', options:)
    2.times { expect { run.call(date) }.to raise_error(Ingestion::GameSyncProvider::Incomplete) }
    expect(adapter).to have_received(:call).once
    expect(Game.count).to eq(0)
  end

  it 'memoizes exceptions after acquisition starts rather than renewing the request budget' do
    allow(adapter).to receive(:call).and_raise(IOError, 'synthetic private details')
    run = described_class.new(season:, dates: [date, date + 1], provider: 'cbbd', options:)
    [date, date + 1].each { |day| expect { run.call(day) }.to raise_error(described_class::Incomplete) }
    expect(adapter).to have_received(:call).once
    expect(run.summary.to_json).not_to include('synthetic private details')
  end
end
