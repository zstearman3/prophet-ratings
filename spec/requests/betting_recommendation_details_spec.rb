# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Betting recommendation details' do
  let(:season) { create(:season, :current) }
  let(:config) { create(:ratings_config_version, current: true) }
  let(:game) { create(:game, season:, start_time: 1.day.from_now, home_team_name: 'BYU', away_team_name: 'Ohio State') }
  let(:snapshots) do
    create_list(:team_season, 2, season:).map do |participant|
      create(:team_rating_snapshot, team_season: participant, ratings_config_version: config)
    end
  end
  let(:prediction) do
    create(:prediction, game:, ratings_config_version: config, home_team_snapshot: snapshots.first,
                        away_team_snapshot: snapshots.last, home_score: 81, away_score: 80, pace: 70)
  end
  let(:odd) do
    create(:game_odd, game:, fetched_at: Time.current, spread_point: -6.5, moneyline_home: -180,
                      moneyline_away: 150, total_points: 170.5)
  end
  let!(:spread) { save_recommendation('spread', team: 'away', vegas_line: 2.5, vegas_odds: -109, ev: 0.064, confidence: 0.555) }
  let!(:moneyline) { save_recommendation('moneyline', team: 'away', vegas_line: nil, vegas_odds: 117, ev: 0.074, confidence: 0.495) }
  let!(:total) do
    save_recommendation('total', team: 'over', vegas_line: 160.5, vegas_odds: -110, model_value: 159.5, ev: 0.06, confidence: 0.555)
  end

  before do
    snapshots.each_with_index do |snapshot, index|
      create(:team_game, game:, team: snapshot.team, team_season: snapshot.team_season, home: index.zero?)
    end
  end

  it 'pairs away recommendations with their saved prices and probabilities despite refreshed market odds' do
    cells = request_details

    aggregate_failures do
      expect(cells[1].text).to include('Recommended bet:', 'Ohio State +2.5', 'Odds: -109', 'Expected ROI: +6.4%',
                                       'Model cover probability: 55.5%')
      expect(cells[2].text).to include('Recommended bet:', 'Ohio State +117', 'Expected ROI: +7.4%',
                                       'Model win probability: 49.5%')
      expect(cells[3].text).to include('Over 160.5', 'Model over probability: 55.5%')
      expect(cells[1].text).to include("Model spread: #{spread.prediction.favorite_line}")
      expect(cells[3].text).to include("Predicted Total: #{total.model_value}")
      expect(cells[1].text).not_to include('BYU -6.5')
      expect(cells[2].text).not_to include('-180')
      expect(cells[3].text).not_to include('170.5')
      expect(response.parsed_body.at_css('tbody tr').text).to include('Ohio State +2.5', 'Ohio State +117', 'Over 160.5')
      expect(cells[1].at_css('[title]')['title']).to include('$6.40 per $100 wagered')
    end
  end

  it 'also identifies home selections and under probabilities' do
    spread.update!(team: 'home', vegas_line: -2.5)
    moneyline.update!(team: 'home', vegas_odds: -142)
    total.update!(team: 'under')

    cells = request_details

    expect(cells[1].text).to include('BYU -2.5')
    expect(cells[2].text).to include('BYU -142')
    expect(cells[3].text).to include('Under 160.5', 'Model under probability: 55.5%')
  end

  it 'labels below-threshold selections as evaluated sides rather than recommendations' do
    [spread, moneyline, total].each { |rec| rec.update!(recommended: false, ev: -0.021) }

    cells = request_details

    cells.drop(1).each do |cell|
      expect(cell.text).to include('No play', 'Evaluated side:', 'Expected ROI: -2.1%')
      expect(cell.text).not_to include('Recommended bet:')
    end
    expect(cells[1].text).to include('Ohio State +2.5')
    expect(cells[2].text).to include('Ohio State +117')
    expect(response.parsed_body.at_css('tbody tr').text.scan('No play').size).to eq(3)
  end

  it 'does not invent the evaluated side for legacy no-play rows that discarded it' do
    [spread, total].each { |rec| rec.update!(team: nil, recommended: false) }

    cells = request_details

    expect(cells[3].text).to include('Model selected-side probability: 55.5%')
    expect(cells[3].text).not_to include('Model cover probability:')
    [cells[1], cells[3]].each do |cell|
      expect(cell.text).to include('No play', 'Evaluated side: Not saved')
      expect(cell.text).not_to include('Recommended bet:')
      expect(cell.at_css('div:nth-child(2)').text).not_to include('BYU', 'Ohio State', 'Over', 'Under')
    end
  end

  it 'suppresses invalid saved picks and their ROI even when current market odds are valid' do
    [spread, moneyline, total].each { |rec| rec.update!(vegas_odds: -1, ev: 53.523) }

    cells = request_details
    row = response.parsed_body.at_css('tbody tr')

    expect(row.text.scan('No recommendation').size).to eq(3)
    %w[spread moneyline total].each { |market| expect(row["data-ev-for-#{market}"]).to eq('-999') }
    expect(cells.drop(1).map { |cell| cell.text.strip }).to eq(['', '', ''])
    expect(response.body).not_to include('5352.3%', 'Recommended bet:')
    expect(BetRecommendation.where(current: true).count).to eq(3)
    expect(moneyline.reload.recommendation).to eq('No play')
  end

  it 'keeps participant-excluded forecasts unavailable even when their saved prices are valid' do
    prediction.update!(home_team_snapshot: snapshots.last, away_team_snapshot: snapshots.first)

    cells = request_details
    row = response.parsed_body.at_css('tbody tr')

    expect(row.text).to include('Forecast unavailable: Participant side mismatch')
    expect(row.text.scan('No recommendation').size).to eq(3)
    %w[spread moneyline total].each { |market| expect(row["data-ev-for-#{market}"]).to eq('-999') }
    expect(cells.drop(1).map { |cell| cell.text.strip }).to eq(['', '', ''])
  end

  it 'uses valid saved prices even when the current market has become invalid' do
    odd.update!(moneyline_home: -1, moneyline_away: -1, spread_home_odds: -1, spread_away_odds: -1)

    cells = request_details

    expect(cells[1].text).to include('Ohio State +2.5', 'Odds: -109')
    expect(cells[2].text).to include('Ohio State +117', 'Expected ROI: +7.4%')
    expect(response.parsed_body.at_css('tbody tr')['data-ev-for-moneyline']).to eq('0.074')
  end

  it 'excludes invalid saved odds from server sorting and client EV attributes in both directions' do
    other = create(:game, season:, start_time: game.start_time + 1.hour, home_team_name: 'Valid Home')
    other_prediction = create(:prediction, game: other, ratings_config_version: config,
                                           home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last)
    other_odds = create(:game_odd, game: other, fetched_at: Time.current)
    create(:bet_recommendation, game: other, prediction: other_prediction, game_odd: other_odds,
                                ratings_config_version: config, current: true, recommended: true,
                                bet_type: 'moneyline', vegas_odds: -110, ev: 0.1)
    moneyline.update!(vegas_odds: -1, ev: 53.523)

    %w[desc asc].each do |direction|
      get '/games/betting', params: { date: game.schedule_date.to_s, sort: 'moneyline', direction: }
      rows = response.parsed_body.css('tr[data-betting-sort-target="row"]')
      expected = direction == 'desc' ? [other, game] : [game, other]
      expect(rows.map { |row| row.at_css('a')['href'] }).to eq(expected.map { |match| "/games/#{match.id}" })
      expect(rows.find { |row| row.text.include?('Ohio State') }['data-ev-for-moneyline']).to eq('-999')
    end
  end

  def save_recommendation(bet_type, **attrs)
    create(:bet_recommendation, game:, prediction:, game_odd: odd, ratings_config_version: config,
                                bet_type:, current: true, recommended: true, **attrs)
  end

  def request_details
    get '/games/betting', params: { date: game.schedule_date.to_s }
    expect(response).to have_http_status(:success)
    response.parsed_body.css('tr.expandable-row td')
  end
end
