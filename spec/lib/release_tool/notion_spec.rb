# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/release_tool/notion')

RSpec.describe ReleaseTool::Notion do
  let(:client) { described_class.new(token: 'synthetic-token') }
  let(:page_id) { '3f517d6b0c2481d89485e095471b9bad' }
  let(:url) { "https://app.notion.com/p/#{page_id}" }
  let(:http) { instance_double(Net::HTTP) }
  let(:response) { Net::HTTPOK.new('1.1', '200', 'OK') }
  let(:document) do
    { 'properties' => { 'Task name' => { 'type' => 'title', 'title' => [{ 'plain_text' => 'Review offseason evidence' }] },
                        'Status' => { 'type' => 'status', 'status' => { 'name' => 'Testing' } } } }
  end

  before do
    allow(client).to receive(:sleep)
    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:request).and_return(response)
    allow(response).to receive(:body).and_return(JSON.generate(document))
  end

  it 'reads linked pages with bounded HTTPS requests and caches repeated references' do
    result = client.tickets("Ticket: #{url}?pvs=4\n[Same](https://www.notion.so/Review-#{page_id})")
    expect(result).to eq([{ title: 'Review offseason evidence', status: 'Testing', url: "https://www.notion.so/#{page_id}" }])
    client.tickets(url)
    expect(http).to have_received(:request).once.with(satisfy do |request|
      request.path == "/v1/pages/#{page_id}" && request['Authorization'] == 'Bearer synthetic-token' &&
        request['Notion-Version'] == '2025-09-03'
    end)
    expect(client).to have_received(:sleep).with(0.35).once
    expect(Net::HTTP).to have_received(:start).with('api.notion.com', 443, use_ssl: true, open_timeout: 10, read_timeout: 20)
  end

  it 'retains ticket links without attempting authentication when no token is configured' do
    result = described_class.new(token: nil).tickets(url)
    expect(result.first).to include(status: 'Notion unavailable', url: "https://www.notion.so/#{page_id}")
    expect(Net::HTTP).not_to have_received(:start)
  end

  it 'ignores unrelated hosts and normalizes hyphenated page IDs' do
    text = "https://notion.so.evil.example/#{page_id} https://app.notion.com/p/3f517d6b-0c24-81d8-9485-e095471b9bad"
    expect(described_class.ids(text)).to eq([page_id])
  end

  it 'retains unavailable status on access failure without logging credentials' do
    denied = Net::HTTPForbidden.new('1.1', '403', 'Forbidden')
    allow(http).to receive(:request).and_return(denied)
    expect { client.tickets(url) }.to output(/lookup.*failed/).to_stderr
    expect(described_class.new(token: nil).tickets(url).first.fetch(:status)).to eq('Notion unavailable')
  end

  it 'retains unavailable status for malformed JSON rather than inventing a ticket status' do
    allow(response).to receive(:body).and_return('invalid JSON')
    result = nil
    expect { result = client.tickets(url) }.to output(/failed/).to_stderr
    expect(result.first.fetch(:status)).to eq('Notion unavailable')
  end
end
