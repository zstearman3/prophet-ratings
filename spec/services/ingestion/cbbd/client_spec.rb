# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe Ingestion::Cbbd::Client do
  let(:directory) { Dir.mktmpdir('cbbd-client') }
  let(:store) { Ingestion::Cbbd::CaptureStore.new(directory) }
  let(:filters) do
    { 'endpoint' => '/games', 'season' => 2026, 'startDateRange' => '2025-11-01T00:00:00Z',
      'endDateRange' => '2025-11-01T23:59:59Z' }
  end
  let(:replies) { [] }
  let(:transport) do
    lambda { |_uri, _key|
      reply = replies.shift
      reply.is_a?(Exception) ? raise(reply) : reply
    }
  end
  let(:waits) { [] }
  let(:client) { described_class.new(store: store, api_key: 'private-sentinel', transport: transport, sleeper: waits.method(:push)) }

  after { FileUtils.remove_entry(directory) }

  def response(status, body = '[]', headers = {})
    { status: status, body: body, headers: headers }
  end

  it 'retains empty success with private permissions and safe echoed secret' do
    replies << response(200, '[]', { 'x-ratelimit-remaining' => '4', 'authorization' => 'private-sentinel' })
    result = client.request(filters)
    expect(result).to include('outcome' => 'success', 'rows' => [])
    expect(result['headers']).to eq('x-ratelimit-remaining' => '4')
    expect(File.stat(directory).mode & 0o777).to eq(0o700)
    expect(Dir.glob("#{directory}/*").map { |path| File.stat(path).mode & 0o777 }.uniq).to eq([0o600])
  end

  [401, 403].each do |status|
    it "does not retry authentication failure #{status}" do
      replies << response(status, 'private-sentinel')
      result = client.request(filters)
      expect(result['outcome']).to eq('authentication')
      expect(client.attempts).to eq(1)
      expect(Dir.glob("#{directory}/*").map { |path| File.read(path) }.join).not_to include('private-sentinel')
    end
  end

  it 'retains each bounded transient attempt without exception messages' do
    replies.push(Net::ReadTimeout.new('private-sentinel'), response(503), response(200))
    expect(client.request(filters)['outcome']).to eq('success')
    expect(client.captures.pluck('outcome')).to eq(%w[timeout transport success])
    expect(waits).to eq([1, 2])
    expect(Dir.glob("#{directory}/*").map { |path| File.read(path) }.join).not_to include('private-sentinel')
  end

  it 'honors retry after and refuses delays beyond the bound' do
    replies.push(response(429, '{}', { 'retry-after' => '31' }), response(200))
    expect(client.request(filters)).to include('outcome' => 'quota', 'retry_exhausted' => true)
    expect(waits).to be_empty
  end

  it 'distinguishes malformed JSON, invalid envelope, redirects and transport' do
    replies.push(response(200, '{'), response(200, '{}'), response(302), response(503), response(503), response(503))
    expect(Array.new(4) { client.request(filters)['outcome'] }).to eq(%w[malformed_json malformed_envelope http transport])
    expect(client.attempts).to eq(6)
  end

  it 'enforces a shared request ceiling including retries' do
    limited = described_class.new(store: store, api_key: 'private-sentinel', transport: transport,
                                  sleeper: waits.method(:push), max_requests: 1)
    replies << response(503)
    expect(limited.request(filters)['outcome']).to eq('request_budget')
    expect(limited.attempts).to eq(1)
  end

  [Net::HTTPBadResponse, Net::ProtocolError].each do |error_class|
    it "retains #{error_class} as a transport failure with finite retries and safe evidence" do
      replies.concat(Array.new(3) { error_class.new('private-sentinel in invalid HTTP response') })
      expect(client.request(filters)['outcome']).to eq('transport')
      expect(client.captures).to all(include('outcome' => 'transport', 'error_class' => error_class.name))
      expect(client.attempts).to eq(3)
      expect(waits).to eq([1, 2])
      expect(Dir.glob("#{directory}/*").map { |path| File.read(path) }.join).not_to include('private-sentinel')
    end
  end

  it 'counts protocol failures against the shared attempt ceiling' do
    limited = described_class.new(store: store, api_key: 'private-sentinel', transport: transport,
                                  sleeper: waits.method(:push), max_requests: 1)
    replies << Net::HTTPBadResponse.new('private-sentinel in invalid HTTP response')
    expect(limited.request(filters)['outcome']).to eq('request_budget')
    expect(limited.attempts).to eq(1)
    expect(limited.captures.sole).to include('outcome' => 'transport', 'error_class' => 'Net::HTTPBadResponse')
  end

  it 'honors HTTP-date retry-after exactly' do
    now = Time.utc(2026, 1, 1)
    allow(Time).to receive(:now).and_return(now)
    replies.push(response(429, '{}', { 'retry-after' => (now + 7).httpdate }), response(200))
    expect(client.request(filters)['outcome']).to eq('success')
    expect(waits).to eq([7])
  end

  it 'never converts a capture write failure into successful acquisition' do
    allow(store).to receive(:capture).and_raise(IOError, 'private storage failed').once
    replies << response(200)
    expect { client.request(filters) }.to raise_error(IOError, 'private storage failed')
  end

  it 'retains malformed binary response evidence without losing the failed attempt' do
    replies << response(200, "\xFF".b)
    expect(client.request(filters)['outcome']).to eq('malformed_json')
    expect(File.binread(Dir.glob("#{directory}/*.body").sole)).to eq("\xFF".b)
  end
end
