# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scraper::ConferenceStandingsScraper do
  subject(:scraper) { described_class.new(year: 2026) }

  let(:html) { Rails.root.join('spec/fixtures/conference_standings.html').read }

  it 'requests the target season and parses visible and commented tables without writes' do
    response = instance_double(HTTParty::Response, code: 200, body: html)
    allow(HTTParty).to receive(:get).with(scraper.source_url, timeout: 30).and_return(response)

    expect { scraper.call }.not_to change(TeamConference, :count)
    expect(scraper.call).to contain_exactly(
      { team_slug: 'first', team_name: 'First University', conference_slug: 'alpha',
        conference_name: 'Alpha Conference', conference_abbreviation: 'ALP' },
      { team_slug: 'second', team_name: 'Second University', conference_slug: 'alpha',
        conference_name: 'Alpha Conference', conference_abbreviation: 'ALP' },
      { team_slug: 'third', team_name: 'Third University', conference_slug: 'beta',
        conference_name: 'Beta Conference', conference_abbreviation: 'BET' }
    )
    expect(scraper.source_url).to end_with('/cbb/seasons/men/2026-standings.html')
  end

  it 'fails clearly for a failed request' do
    allow(HTTParty).to receive(:get).and_return(instance_double(HTTParty::Response, code: 403))
    expect { scraper.call }.to raise_error(described_class::Error, /HTTP 403/)
  end

  it 'fails clearly for network errors' do
    allow(HTTParty).to receive(:get).and_raise(Timeout::Error)
    expect { scraper.call }.to raise_error(described_class::Error, /request failed/)
  end

  it 'rejects an unsupported page' do
    expect { scraper.parse('<html>Access denied</html>') }.to raise_error(described_class::Error, /no conference tables/)
  end

  it 'rejects a row without a stable source team link' do
    expect { scraper.parse(html.sub('/schools/first/', '/schools//')) }.to raise_error(described_class::Error, /Invalid/)
  end

  it 'rejects a response containing a different season' do
    expect { scraper.parse(html.gsub('2026.html', '2025.html')) }.to raise_error(described_class::Error, /Invalid conference link/)
  end

  it 'rejects duplicate source team memberships across conferences' do
    expect { scraper.parse(html.sub('/schools/third/', '/schools/first/')) }.to raise_error(described_class::Error, /Duplicate source team/)
  end

  it 'rejects duplicate conference tables' do
    expect { scraper.parse(html + html) }.to raise_error(described_class::Error, /Duplicate source conference/)
  end

  it 'rejects empty conference tables' do
    expect { scraper.parse('<table id="standings_alpha"><tbody></tbody></table>') }.to raise_error(described_class::Error, /Empty source/)
  end
end
