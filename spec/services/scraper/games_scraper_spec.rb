# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scraper::GamesScraper do
  let(:date) { Date.new(2026, 2, 18) }
  let(:scraper) { described_class.new(date) }
  let(:schedule_url) { scraper.send(:schedule_url, date) }
  let(:response) { instance_double(HTTParty::Response, body: schedule_html, success?: true) }
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
      home_team_score: 71,
      away_team_score: 62,
      date: Time.zone.parse('February 18, 2026'),
      box_score_location: 'Chapel Hill, NC',
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
      date: Game::SCHEDULE_TIME_ZONE.parse("#{date} 7:00pm").in_time_zone,
      away_team_stats: {},
      home_team_stats: {},
      source_completed: false,
      source_completion_evidence: nil,
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
    completed_only_response = instance_double(HTTParty::Response, body: completed_only_body, success?: true)
    allow(HTTParty).to receive(:get).with(schedule_url).and_return(completed_only_response)
    allow(scraper).to receive(:scrape_game).with(completed_url).and_return(completed_game_payload)

    expect(scraper.to_json).to eq([completed_game_payload])
    expect(scraper).to have_received(:scrape_game).once
  end

  it 'returns a time value for scheduled games when no tip time is provided' do
    start_time = scraper.send(:scheduled_start_time, nil)

    expect(start_time).to be_a(ActiveSupport::TimeWithZone)
    expect(start_time.to_date).to eq(date)
  end

  it 'parses scheduled tip times that include timezone labels' do
    start_time = scraper.send(:scheduled_start_time, '7:00p ET')

    expect(start_time).to be_a(ActiveSupport::TimeWithZone)
    expect(start_time).to eq(Game::SCHEDULE_TIME_ZONE.parse("#{date} 7:00pm").in_time_zone)
    expect(Game.schedule_date_for(start_time)).to eq(date)
  end

  it 'returns a time value for completed games from scorebox metadata' do
    completed_boxscore_html = <<~HTML
      <div class="scorebox">
        <div>
          <strong><a>Duke</a></strong>
          <div class="score">62</div>
        </div>
        <div>
          <strong><a>North Carolina</a></strong>
          <div class="score">71</div>
        </div>
      </div>
      <div class="scorebox_meta">
        <div>February 18, 2026</div>
        <div> Chapel Hill, NC </div>
      </div>
      <table class="stats_table">
        <tfoot>
          <tr><td data-stat="mp">200</td></tr>
          <tr></tr>
          <tr><td data-stat="mp">200</td></tr>
        </tfoot>
      </table>
    HTML
    completed_response = instance_double(HTTParty::Response, body: completed_boxscore_html, success?: true)
    allow(HTTParty).to receive(:get).with(scraper.send(:game_url, completed_url)).and_return(completed_response)

    game = scraper.send(:scrape_game, completed_url)

    expect(game[:date]).to be_a(ActiveSupport::TimeWithZone)
    expect(game[:date].to_date).to eq(date)
    expect(game[:box_score_location]).to eq('Chapel Hill, NC')
  end

  it 'fetches the schedule once and respects exact batch sizes' do
    allow(scraper).to receive(:scrape_game).with(completed_url).and_return(completed_game_payload)
    expect(scraper.game_count).to eq(2)
    expect(scraper.to_json_in_batches(0, 1)).to eq([completed_game_payload])
    expect(scraper.to_json_in_batches(1, 1).size).to eq(1)
    expect(HTTParty).to have_received(:get).with(schedule_url).once
  end

  it 'recognizes a valid empty schedule' do
    allow(response).to receive(:body).and_return('<div class="game_summaries"></div>')
    expect(scraper.game_count).to eq(0)
  end

  it 'rejects error responses instead of reporting an empty date' do
    allow(response).to receive_messages(success?: false, code: 503)
    expect { scraper.game_count }.to raise_error(described_class::SourceError, /503/)
  end

  it 'rejects unavailable or unrecognized pages with successful HTTP responses' do
    allow(response).to receive(:body).and_return('<html><h1>Access denied</h1></html>')
    expect { scraper.game_count }.to raise_error(described_class::SourceError, /Unrecognized/)
  end

  it 'rejects malformed scheduled rows rather than silently dropping them' do
    allow(response).to receive(:body).and_return('<div class="game_summaries"><div class="gender-m"></div></div>')
    expect { scraper.game_count }.to raise_error(described_class::SourceError, /Malformed/)
  end

  it 'rejects a malformed boxscore instead of returning a nameless scheduled game' do
    malformed_response = instance_double(HTTParty::Response, body: '<div class="scorebox"><div></div><div></div></div>', success?: true)
    allow(HTTParty).to receive(:get).with(scraper.send(:game_url, completed_url)).and_return(malformed_response)
    expect { scraper.to_json_in_batches(0, 1) }.to raise_error(described_class::SourceError, /Missing boxscore teams/)
  end

  context 'with saved source layouts' do
    let(:date) { Date.new(2024, 11, 4) }
    let(:completed_url) { '/cbb/boxscores/2024-11-04-20-kansas.html' }
    let(:schedule_html) { fixture_html('unlinked_final') }

    def fixture_html(name)
      Rails.root.join("spec/fixtures/games_scraper/#{name}.html").read
    end

    def stub_boxscore(html)
      boxscore_response = instance_double(HTTParty::Response, body: html, success?: true)
      allow(HTTParty).to receive(:get).with(scraper.send(:game_url, completed_url)).and_return(boxscore_response)
    end

    it 'preserves unlinked names without poll ranks and emits score-only final evidence' do
      expect(scraper.to_json).to contain_exactly(hash_including(
                                                   away_team: 'Howard', home_team: 'Kansas', away_team_score: 57, home_team_score: 87,
                                                   away_team_stats: {}, home_team_stats: {}, url: schedule_url,
                                                   source_completed: true, source_completion_evidence: 'schedule_final'
                                                 ))
    end

    it 'retains a known team alias matchup with an unmatched unlinked opponent' do
      team = create(:team, school: 'Kansas Jayhawks')
      create(:team_alias, team:, value: 'Kansas', source: 'sports_reference')

      expect(scraper.to_json_for_team(team)).to contain_exactly(hash_including(away_team: 'Howard', home_team: 'Kansas'))
    end

    it 'uses consistent winner and loser markup when no final label or link remains' do
      allow(response).to receive(:body).and_return(schedule_html.sub('F<span class="no_mobile">inal</span>', ''))

      expect(scraper.to_json.first).to include(source_completed: true, source_completion_evidence: 'schedule_winner_loser')
    end

    it 'keeps unlinked scheduled names and unavailable scores distinct from finals' do
      allow(response).to receive(:body).and_return(fixture_html('scheduled'))

      expect(scraper.to_json.first).to include(
        away_team: 'Howard', home_team: 'Kansas', away_team_score: nil, home_team_score: nil,
        source_completed: false, source_completion_evidence: nil
      )
    end

    it 'does not infer completion from scores on a past date alone' do
      allow(response).to receive(:body).and_return(fixture_html('ambiguous_scores'))

      expect(scraper.to_json.first).to include(source_completed: false, source_completion_evidence: nil)
    end

    %w[Canceled Cancelled Postponed Live Halftime Scheduled].each do |status|
      it "rejects a linked #{status} schedule even when its boxscore has valid final scores" do
        html = fixture_html('canceled_linked').sub('Canceled', status)
        allow(response).to receive(:body).and_return(html)
        stub_boxscore(fixture_html('detailed_final'))

        expect { scraper.to_json }.to raise_error(described_class::SourceError, /Nonfinal/)
      end
    end

    ['87', '', '-1', 'unknown'].each do |score|
      it "rejects a final with invalid or tied away score #{score.inspect}" do
        allow(response).to receive(:body).and_return(fixture_html('malformed_final').sub('>unknown<', ">#{score}<"))

        expect { scraper.to_json }.to raise_error(described_class::SourceError, /final scores/)
      end
    end

    it 'rejects winner markup that contradicts the final scores' do
      allow(response).to receive(:body).and_return(schedule_html.sub('>57<', '>97<'))

      expect { scraper.to_json }.to raise_error(described_class::SourceError, /winner/)
    end

    it 'preserves an explicit zero score without inventing missing statistics' do
      allow(response).to receive(:body).and_return(schedule_html.sub('>57<', '>0<'))

      expect(scraper.to_json.first).to include(away_team_score: 0, source_completed: true, away_team_stats: {})
    end

    it 'extracts ordinary linked finals with basic statistics assigned to their own teams' do
      allow(response).to receive(:body).and_return(fixture_html('linked_final'))
      stub_boxscore(fixture_html('detailed_final'))

      game = scraper.to_json.first

      expect(game).to include(away_team: 'Howard', home_team: 'Kansas', source_completed: true, source_completion_evidence: 'boxscore')
      expect(game[:away_team_stats]).to include(points: '57')
      expect(game[:home_team_stats]).to include(points: '87')
    end

    it 'recognizes a score-only boxscore with plain-text names' do
      stub_boxscore(fixture_html('score_only'))

      expect(scraper.send(:scrape_game, completed_url)).to include(
        away_team: 'Howard', home_team: 'Kansas', away_team_score: 57, home_team_score: 87,
        source_completed: true, source_completion_evidence: 'boxscore', away_team_stats: {}, home_team_stats: {}
      )
    end

    it 'does not shift home statistics onto the away team when its basic table is absent' do
      document = Nokogiri::HTML(fixture_html('detailed_final'))
      document.at_css('#box-score-basic-howard').remove
      stub_boxscore(document.to_html)

      game = scraper.send(:scrape_game, completed_url)

      expect(game[:away_team_stats]).to eq({})
      expect(game[:home_team_stats]).to include(points: '87')
    end

    it 'leaves unidentifiable plain-text team statistics unavailable' do
      document = Nokogiri::HTML(fixture_html('detailed_final'))
      document.css('.scorebox strong a').each { |anchor| anchor.replace(anchor.children) }
      stub_boxscore(document.to_html)

      expect(scraper.send(:scrape_game, completed_url)).to include(away_team_stats: {}, home_team_stats: {})
    end

    it 'does not synthesize counts for missing statistic cells' do
      document = Nokogiri::HTML(fixture_html('detailed_final'))
      document.css('#box-score-basic-howard [data-stat="fg"]').remove
      stub_boxscore(document.to_html)

      expect(scraper.send(:scrape_game, completed_url)[:away_team_stats][:field_goals_made]).to be_blank
    end

    it 'rejects nonfinal boxscore status even when scores are valid' do
      stub_boxscore(fixture_html('score_only').sub('November 4, 2024', 'November 4, 2024 Live'))

      expect { scraper.send(:scrape_game, completed_url) }.to raise_error(described_class::SourceError, /Nonfinal/)
    end

    it 'rejects bare arbitrary scored containers without recognized boxscore context' do
      stub_boxscore('<div class="scorebox"><div><strong>A</strong><div class="score">1</div></div>' \
                    '<div><strong>B</strong><div class="score">2</div></div></div>')

      expect { scraper.send(:scrape_game, completed_url) }.to raise_error(described_class::SourceError, /Unrecognized/)
    end

    %w[Howard Kansas].each do |unlinked_team|
      it "retains #{unlinked_team} when only that schedule name is unlinked" do
        document = Nokogiri::HTML(fixture_html('linked_final'))
        document.css('td:first-child a').find { |anchor| anchor.text == unlinked_team }.then { |anchor| anchor.replace(anchor.children) }
        document.css('td.gamelink a').each { |anchor| anchor.replace(anchor.children) }
        allow(response).to receive(:body).and_return(document.to_html)

        expect(scraper.to_json.first).to include(away_team: 'Howard', home_team: 'Kansas', source_completed: true)
      end
    end

    it 'filters by the known school when its opponent is unlinked' do
      team = create(:team, school: 'Kansas')

      expect(scraper.to_json_for_team(team)).to contain_exactly(hash_including(away_team: 'Howard', home_team: 'Kansas'))
    end

    ['87', '', 'bad', '-1'].each do |score|
      it "rejects a recognized boxscore with invalid or tied score #{score.inspect}" do
        stub_boxscore(fixture_html('score_only').sub('>57<', ">#{score}<"))

        expect { scraper.send(:scrape_game, completed_url) }.to raise_error(described_class::SourceError, /final scores/)
      end
    end

    it 'rejects contradictory winner and loser classes on the same row' do
      html = schedule_html.sub('class="loser"', 'class="winner loser"').sub('class="winner"', 'class="loser"')
      allow(response).to receive(:body).and_return(html)

      expect { scraper.to_json }.to raise_error(described_class::SourceError)
    end

    ['<div>November 4, 2024</div><div>Live</div>',
     '<div><span>November 4, 2024</span><span>Live</span></div>',
     '<div>November 4, 2024</div><div>In-progress</div>'].each do |metadata|
      it "rejects nonfinal boxscore metadata with preserved node boundaries: #{metadata}" do
        document = Nokogiri::HTML(fixture_html('score_only'))
        document.at_css('.scorebox_meta').inner_html = metadata
        stub_boxscore(document.to_html.gsub(/>\s+</, '><'))

        expect { scraper.send(:scrape_game, completed_url) }.to raise_error(described_class::SourceError, /Nonfinal/)
      end
    end

    %w[Live In-progress].each do |status|
      it "rejects a minified linked Final and #{status} schedule before fetching its boxscore" do
        document = Nokogiri::HTML(fixture_html('linked_final'))
        document.css('table.teams td:nth-child(3)')[1].content = status
        allow(response).to receive(:body).and_return(document.to_html.gsub(/>\s+</, '><'))
        stub_boxscore(fixture_html('detailed_final'))

        expect { scraper.to_json }.to raise_error(described_class::SourceError, /Nonfinal/)
        expect(HTTParty).not_to have_received(:get).with(scraper.send(:game_url, completed_url))
      end
    end

    ['tr.loser', 'tr.winner'].each do |selector|
      it "rejects contradictory winner/loser outcome classes on #{selector}" do
        document = Nokogiri::HTML(fixture_html('unlinked_final'))
        document.at_css(selector)['class'] = 'winner loser'
        allow(response).to receive(:body).and_return(document.to_html)

        expect { scraper.to_json }.to raise_error(described_class::SourceError, /outcome/)
      end
    end

    it 'rejects adjacent Final and Live spans inside a linked status cell before fetching the boxscore' do
      document = Nokogiri::HTML(fixture_html('linked_final'))
      status_cell = document.at_css('td.gamelink')
      status_cell.at_css('a').inner_html = '<span>Final</span>'
      status_cell.add_child('<span>Live</span>')
      allow(response).to receive(:body).and_return(document.to_html.gsub(/>\s+</, '><'))
      stub_boxscore(fixture_html('detailed_final'))

      expect { scraper.to_json }.to raise_error(described_class::SourceError, /Nonfinal/)
      expect(HTTParty).not_to have_received(:get).with(scraper.send(:game_url, completed_url))
    end
  end
end
