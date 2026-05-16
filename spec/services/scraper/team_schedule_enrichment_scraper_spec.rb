# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scraper::TeamScheduleEnrichmentScraper do
  let(:season) { create(:season, year: 2026) }
  let(:team) { create(:team, school: 'Michigan', slug: 'michigan', url: '/cbb/schools/michigan/men/') }
  let(:scraper) { described_class.new(team:, season:) }
  let(:schedule_url) { 'https://www.sports-reference.com/cbb/schools/michigan/men/2026-schedule.html' }
  let(:response) { instance_double(HTTParty::Response, body: schedule_html, code: 200) }
  let(:expected_rows) do
    [
      expected_row(date: Date.new(2025, 11, 3), start_time: '2025-11-03 8:30pm', opponent_name: 'Oakland',
                   game_location: '', venue_name: 'Crisler Arena', box_score_url: '/cbb/boxscores/2025-11-03-00-michigan.html'),
      expected_row(date: Date.new(2025, 11, 11), start_time: '2025-11-11 6:30pm', opponent_name: 'Wake Forest',
                   game_location: 'N', venue_name: 'Little Caesars Arena', box_score_url: '/cbb/boxscores/2025-11-11-00-michigan.html'),
      expected_row(date: Date.new(2025, 11, 14), start_time: '2025-11-14 9:00pm', opponent_name: 'Texas Christian',
                   game_location: '@', venue_name: 'Ed & Rae Schollmaier Arena',
                   box_score_url: '/cbb/boxscores/2025-11-14-21-texas-christian.html')
    ]
  end
  let(:schedule_html) do
    <<~HTML
      <div class="table_container" id="div_schedule">
        <table class="sortable stats_table" id="schedule">
          <tbody>
            <tr>
              <th scope="row" class="right" data-stat="g">1</th>
              <td class="left" data-stat="date_game" csk="2025-11-03">
                <a href="/cbb/boxscores/2025-11-03-00-michigan.html">Mon, Nov 3, 2025</a>
              </td>
              <td class="left" data-stat="time_game">8:30p</td>
              <td class="left iz" data-stat="game_location"></td>
              <td class="left" data-stat="opp_name"><a href="/cbb/schools/oakland/men/2026.html">Oakland</a></td>
              <td class="left" data-stat="arena">Crisler Arena</td>
            </tr>
            <tr>
              <th scope="row" class="right" data-stat="g">2</th>
              <td class="left" data-stat="date_game" csk="2025-11-11">
                <a href="/cbb/boxscores/2025-11-11-00-michigan.html">Tue, Nov 11, 2025</a>
              </td>
              <td class="left" data-stat="time_game">6:30p</td>
              <td class="left" data-stat="game_location">N</td>
              <td class="left" data-stat="opp_name"><a href="/cbb/schools/wake-forest/men/2026.html">Wake Forest</a></td>
              <td class="left" data-stat="arena">Little Caesars Arena</td>
            </tr>
            <tr>
              <th scope="row" class="right" data-stat="g">3</th>
              <td class="left" data-stat="date_game" csk="2025-11-14">
                <a href="/cbb/boxscores/2025-11-14-21-texas-christian.html">Fri, Nov 14, 2025</a>
              </td>
              <td class="left" data-stat="time_game">9:00p</td>
              <td class="left" data-stat="game_location">@</td>
              <td class="left" data-stat="opp_name"><a href="/cbb/schools/texas-christian/men/2026.html">Texas Christian</a></td>
              <td class="left" data-stat="arena">Ed &amp; Rae Schollmaier Arena</td>
            </tr>
            <tr class="thead">
              <th data-stat="g">G</th>
            </tr>
          </tbody>
        </table>
      </div>
    HTML
  end

  before do
    allow(scraper).to receive(:sleep)
    allow(HTTParty).to receive(:get).with(schedule_url).and_return(response)
  end

  it 'parses venue rows from a Sports Reference team schedule table' do
    expect(scraper.schedule_data).to eq(expected_rows)
  end

  it 'returns no rows when the schedule response is not successful' do
    allow(HTTParty).to receive(:get).with(schedule_url).and_return(instance_double(HTTParty::Response, code: 503))

    expect(scraper.schedule_data).to eq([])
  end

  it 'returns no rows when the schedule request fails' do
    allow(HTTParty).to receive(:get).with(schedule_url).and_raise(Timeout::Error)

    expect(scraper.schedule_data).to eq([])
  end

  def expected_row(attrs)
    {
      date: attrs[:date],
      start_time: ActiveSupport::TimeZone['Eastern Time (US & Canada)'].parse(attrs[:start_time]).in_time_zone,
      opponent_name: attrs[:opponent_name],
      game_location: attrs[:game_location],
      venue_name: attrs[:venue_name],
      box_score_url: attrs[:box_score_url],
      source_url: schedule_url
    }
  end
end
