# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/driver')

RSpec.describe OffseasonPerformance::Client do
  it 'preserves per-client cookies and CSRF while encoding post bodies only for POST' do
    client = described_class.new('cookies' => { 'session' => 'one' }, 'token' => 'csrf-one')
    uri = URI('http://web:3000/admin/example')
    options = { headers: client.headers('request-one'), values: { 'mode' => 'initialize' } }
    get = described_class.build_request(Net::HTTP::Get, uri, options)
    post = described_class.build_request(Net::HTTP::Post, uri, options)
    expect(get.body).to be_nil
    expect(post.body).to eq('mode=initialize')
    expect(post.to_hash).to include('cookie' => ['session=one'], 'x-csrf-token' => ['csrf-one'],
                                    'x-benchmark-id' => ['request-one'])
    expect(described_class.new.headers('request-two')).not_to have_key('X-CSRF-Token')
  end

  it 'disables automatic retries before dispatching a request and propagates a broken connection' do
    uri = URI('http://web:3000/admin/example')
    request = Net::HTTP::Get.new(uri)
    http = instance_double(Net::HTTP)
    events = []
    allow(http).to receive(:max_retries=) { |value| events << [:retries, value] }
    allow(http).to receive(:request) do |sent|
      events << [:request, sent]
      raise EOFError, 'broken connection'
    end
    allow(Net::HTTP).to receive(:start).with(uri.host, uri.port, read_timeout: 180, open_timeout: 5).and_yield(http)
    expect { described_class.perform(uri, request) }.to raise_error(EOFError)
    expect(events).to eq([[:retries, 0], [:request, request]])
    expect(http).to have_received(:request).once
  end
end
