# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/telemetry')

RSpec.describe OffseasonPerformance::Telemetry do
  it 'records SQL scalars and cache hits without retaining notification payloads or bindings' do
    Tempfile.create do |file|
      allow(ENV).to receive(:fetch).with('BENCHMARK_TELEMETRY').and_return(file.path)
      allow(described_class).to receive(:memory).and_return({ 'current_bytes' => 10 })
      described_class.install
      described_class.measure('test', 'one') do
        ActiveSupport::Notifications.instrument('sql.active_record', name: 'SQL', sql: 'SELECT 1', binds: ['private'])
        ActiveSupport::Notifications.instrument('sql.active_record', name: 'SQL', cached: true)
      end
      data = JSON.parse(File.read(file.path))
      expect(data).to include('id' => 'one', 'sql_count' => 1, 'cache_hits' => 1, 'current_bytes' => 10)
      expect(data).to have_key('gc_count_process_delta')
      expect(data.keys).not_to include('sql', 'binds', 'payload')
      expect(Thread.current[:offseason_performance]).to be_nil
    end
  end

  it 'restores an enclosing context after exceptions and isolates other threads' do
    Tempfile.create do |file|
      allow(ENV).to receive(:fetch).with('BENCHMARK_TELEMETRY').and_return(file.path)
      allow(described_class).to receive(:memory).and_return({})
      observed = nil
      expect do
        described_class.measure('test', 'broken') do
          observed = Thread.new { Thread.current[:offseason_performance] }.value
          raise 'expected failure'
        end
      end.to raise_error('expected failure')
      expect(observed).to be_nil
      expect(Thread.current[:offseason_performance]).to be_nil
      expect(JSON.parse(File.read(file.path))['elapsed']).to be >= 0
    end
  end
end
