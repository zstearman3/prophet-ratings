# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/driver')

RSpec.describe OffseasonPerformance::Driver do
  before do
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with('/benchmark/fixture.json').and_return('{"season_id":1}')
    allow(File).to receive(:read).with('/benchmark/sessions.json').and_return('[{}, {}, {}]')
  end

  it 'uses three independent clients concurrently and retains ordinal order' do
    driver = described_class.new('status', 'concurrent')
    ready = Queue.new
    release = Queue.new
    allow(driver).to receive(:sample) do |client|
      ready << client
      release.pop
      {}
    end
    thread = Thread.new { driver.concurrent_requests(3) }
    clients = Array.new(3) { ready.pop }
    expect(clients.uniq.size).to eq(3)
    3.times { release << true }
    expect(thread.value.pluck('ordinal')).to eq([0, 1, 2])
  ensure
    thread&.kill
  end

  it 'reads a fresh wall clock at each end of the HTTP sample' do
    driver = described_class.new('status', 'serial')
    allow(Time).to receive(:now).and_return(Time.at(100).utc, Time.at(102).utc)
    response = instance_double(Net::HTTPResponse, code: '200', body: '{"status":"review","updated_at":"time"}')
    allow(driver).to receive(:timed_request).and_return([response, 2])
    allow(OffseasonPerformance::Measurements).to receive(:http).and_return('valid' => true)
    expect(driver.http_sample(nil, nil)).to include('started_at' => 100.0, 'finished_at' => 102.0)
    expect(Time).to have_received(:now).twice
  end

  it 'retains completed serial samples when a later request fails' do
    driver = described_class.new('status', 'serial')
    values = [1, 2]
    allow(driver).to receive(:sample) { values.shift || raise('failed request') }
    result = { 'samples' => [] }
    expect { driver.serial_requests(result, 'samples', 30) }.to raise_error('failed request')
    expect(result['samples']).to eq([1, 2])
  end
end
