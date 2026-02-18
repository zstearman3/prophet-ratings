# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scraper::GamesScraper do
  let(:date) { Date.new(2026, 2, 18) }
  let(:scraper) { described_class.new(date) }
  let(:schedule_url) { scraper.send(:schedule_url, date) }
  let(:response) { instance_double(HTTParty::Response, body: schedule_html) }
  let(:completed_url) { '/cbb/boxscores/2026-02-18-unc-duke.html' }
  let(:schedule_html) do
    <<~HTML
      <div class="game_summaries">
        <div class="game_summary nohover gender-m">
          <table class="teams">
            <tbody>
              <tr class="loser">
                <td><a href="/cbb/schools/duke/men/2026.html">Duke</a></td>
                <td class="right">62</td>
                <td class="right gamelink"><a href="#{completed_url}">Box Score</a></td>
              </tr>
              <tr class="winner">
                <td><a href="/cbb/schools/north-carolina/men/2026.html">North Carolina</a></td>
                <td class="right">71</td>
                <td class="right"></td>
              </tr>
            </tbody>
          </table>
        </div>
        <div class="game_summary nohover gender-m">
          <table class="teams">
            <tbody>
              <tr class="loser">
                <td><a href="/cbb/schools/alabama-state/men/2026.html">Alabama State</a></td>
                <td class="right"></td>
                <td class="right gamelink"></td>
              </tr>
              <tr class="loser">
                <td><a href="/cbb/schools/bethune-cookman/men/2026.html">Bethune-Cookman</a></td>
                <td class="right"></td>
                <td class="right">7:00p</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    HTML
  end
  let(:completed_game_payload) do
    {
      home_team: 'North Carolina',
      away_team: 'Duke',
      home_team_score: '71',
      away_team_score: '62',
      date: 'February 18, 2026',
      location: 'Chapel Hill, NC',
      away_team_stats: { minutes: '200' },
      home_team_stats: { minutes: '200' },
      url: completed_url
    }
  end

  before do
    allow(scraper).to receive(:sleep)
    allow(HTTParty).to receive(:get).with(schedule_url).and_return(response)
  end

  it 'counts completed and unplayed games from the schedule page' do
    expect(scraper.game_count).to eq(2)
  end

  it 'returns scheduled rows for games without a boxscore URL' do
    allow(scraper).to receive(:scrape_game).with(completed_url).and_return(completed_game_payload)

    games = scraper.to_json
    scheduled_game_payload = {
      home_team: 'Bethune-Cookman',
      away_team: 'Alabama State',
      home_team_score: nil,
      away_team_score: nil,
      date: Time.zone.parse("#{date} 7:00pm"),
      location: nil,
      away_team_stats: {},
      home_team_stats: {},
      url: schedule_url
    }

    expect(games).to eq([completed_game_payload, scheduled_game_payload])
    expect(scraper).to have_received(:scrape_game).once
  end

  it 'includes scheduled team games when filtering by team' do
    team = create(:team, school: 'Bethune-Cookman', slug: 'bethune-cookman', url: 'bethune-cookman')
    create(:team_alias, team:, value: 'B-CU', source: 'sports_reference')

    games = scraper.to_json_for_team(team)

    expect(games.size).to eq(1)
    expect(games.first[:home_team]).to eq('Bethune-Cookman')
    expect(games.first[:away_team]).to eq('Alabama State')
  end

  it 'keeps legacy completed-game scraping behavior for completed-only schedules' do
    completed_only_body = <<~HTML
      <div class="game_summaries">
        <div class="game_summary nohover gender-m">
          <table class="teams">
            <tbody>
              <tr class="loser">
                <td><a href="/cbb/schools/duke/men/2026.html">Duke</a></td>
                <td class="right">62</td>
                <td class="right gamelink"><a href="#{completed_url}">Box Score</a></td>
              </tr>
              <tr class="winner">
                <td><a href="/cbb/schools/north-carolina/men/2026.html">North Carolina</a></td>
                <td class="right">71</td>
                <td class="right"></td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    HTML
    completed_only_response = instance_double(HTTParty::Response, body: completed_only_body)
    allow(HTTParty).to receive(:get).with(schedule_url).and_return(completed_only_response)
    allow(scraper).to receive(:scrape_game).with(completed_url).and_return(completed_game_payload)

    expect(scraper.to_json).to eq([completed_game_payload])
    expect(scraper).to have_received(:scrape_game).once
  end
end
