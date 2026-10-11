# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scraper::CoachingChangesScraper do
  subject(:scraper) { described_class.new(year: 2027) }

  let(:html) { file_fixture('coaching_changes/tracker.html').read }
  let(:data) { file_fixture('coaching_changes/rows.json').read }
  let(:request_url) do
    'https://hoopdirt.com/wp-admin/admin-ajax.php?table_id=876543&target_action=get-all-data&skip_rows=0&limit_rows=0&ninja_table_public_nonce=fresh'
  end

  before do
    allow(HTTParty).to receive(:get).with(scraper.source_url, timeout: 30, follow_redirects: false)
                                    .and_return(instance_double(HTTParty::Response, code: 200, body: html))
    allow(HTTParty).to receive(:get).with(request_url, timeout: 30, follow_redirects: false)
                                    .and_return(instance_double(HTTParty::Response, code: 200, body: data))
  end

  it 'discovers the annual D1 request and ignores other divisions' do
    expect(scraper.source_url).to eq('https://hoopdirt.com/2026-coaching-changes-tracker/')
    expect(scraper.call.pluck(:school)).to eq(['Alpha University', 'Beta University'])
    expect(HTTParty).to have_received(:get).with(request_url, timeout: 30, follow_redirects: false)
  end

  it 'discovers changed table IDs and nonces from fresh HTML on retries' do
    scraper.call
    revised_url = request_url.sub('876543', '991234').sub('fresh', 'renewed')
    revised_html = html.sub('876543', '991234').sub('fresh', 'renewed')
    allow(HTTParty).to receive(:get).with(scraper.source_url, timeout: 30, follow_redirects: false)
                                    .and_return(instance_double(HTTParty::Response, code: 200, body: revised_html))
    allow(HTTParty).to receive(:get).with(revised_url, timeout: 30, follow_redirects: false)
                                    .and_return(instance_double(HTTParty::Response, code: 200, body: data))
    expect(scraper.call.size).to eq(2)
    expect(HTTParty).to have_received(:get).with(revised_url, timeout: 30, follow_redirects: false)
  end

  it 'rejects missing or wrong-year D1 tables' do
    html.replace('<html>No table</html>')
    expect { scraper.call }.to raise_error(described_class::Error, /Missing/)
  end

  it 'rejects malformed script JSON and table rows' do
    html.sub!('"columns":', 'BROKEN:')
    expect { scraper.call }.to raise_error(described_class::Error, /Malformed/)
  end

  it 'rejects unexpected empty input' do
    data.replace('[]')
    expect { scraper.call }.to raise_error(described_class::Error, /empty/)
  end

  it 'rejects malformed row labels and duplicate schools' do
    data.replace('[{"value":{"school":"Incomplete"}}]')
    expect { scraper.call }.to raise_error(described_class::Error, /Malformed/)
    data.replace(file_fixture('coaching_changes/rows.json').read.sub('Beta University', 'Alpha University'))
    expect { scraper.call }.to raise_error(described_class::Error, /Duplicate/)
  end

  it 'rejects untrusted request locations and partial tables' do
    html.sub!('hoopdirt.com/wp-admin', 'example.test/wp-admin')
    expect { scraper.call }.to raise_error(described_class::Error, /location/)
    html.replace(file_fixture('coaching_changes/tracker.html').read.sub('"limit_rows":0', '"limit_rows":10'))
    expect { scraper.call }.to raise_error(described_class::Error, /partial/)
  end

  it 'fails visibly on unsuccessful HTTP and network errors' do
    allow(HTTParty).to receive(:get).and_return(instance_double(HTTParty::Response, code: 403))
    expect { scraper.call }.to raise_error(described_class::Error, /HTTP 403/)
    allow(HTTParty).to receive(:get).and_raise(SocketError)
    expect { scraper.call }.to raise_error(described_class::Error, /request failed/)
  end

  it 'fails visibly on table-request errors and invalid JSON' do
    allow(HTTParty).to receive(:get).with(request_url, timeout: 30, follow_redirects: false)
                                    .and_return(instance_double(HTTParty::Response, code: 500))
    expect { scraper.call }.to raise_error(described_class::Error, /HTTP 500/)
    allow(HTTParty).to receive(:get).with(request_url, timeout: 30, follow_redirects: false)
                                    .and_return(instance_double(HTTParty::Response, code: 200, body: 'not JSON'))
    expect { scraper.call }.to raise_error(described_class::Error, /Malformed/)
  end

  it 'requires an explicit ending-year integer' do
    [nil, 1, 10_000, '2027oops', '2027.5'].each do |year|
      expect { described_class.new(year:) }.to raise_error(ArgumentError)
    end
  end
end
