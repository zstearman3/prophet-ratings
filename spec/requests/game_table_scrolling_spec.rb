# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Game table scrolling' do
  let(:date) { Date.new(2026, 3, 14) }

  %w[schedule betting].each do |page|
    it "keeps the empty #{page} table inside a labeled scrolling region" do
      get "/games/#{page}", params: { date: date.to_s }

      document = response.parsed_body
      region = document.at_css('[role="region"][tabindex="0"]')
      expect(response).to have_http_status(:success)
      expect(region['aria-label']).to be_present
      expect(document.at_css("##{region['aria-describedby']}").text).to include('Scroll horizontally')
      expect(region.at_css('table tbody td')['colspan']).to eq('4')
      expect(region.text).to include(page == 'schedule' ? 'No games scheduled' : 'No games with odds')
      expect(document.at_css('input[type="date"]')['value']).to eq(date.to_s)
      expect(document.at_css('input[type="submit"]')['value']).to eq('Go')
    end
  end

  it 'preserves final scores, matchup links and missing predictions in the schedule' do
    game = create(:game, season: create(:season, :current), start_time: date.noon,
                         status: :final, minutes: 40, home_team_score: 70, away_team_score: 65)

    get '/games/schedule', params: { date: date.to_s }

    region = response.parsed_body.at_css('[role="region"]')
    expect(region.at_css("a[href='/games/#{game.id}']")).to be_present
    expect(region.css('tbody td')[2].text.strip).to eq('65 - 70')
    expect(region.text).to include('No prediction')
  end

  it 'preserves betting sort links, recommendations and expanded details inside the region' do
    config = create(:ratings_config_version, name: 'v1.2-default', current: true)
    game = create(:game, season: create(:season, :current), start_time: date.noon,
                         home_team_name: 'A Very Long Synthetic University Team Name')
    home_snapshot = create(:team_rating_snapshot, ratings_config_version: config,
                                                  team_season: create(:team_season, season: game.season))
    away_snapshot = create(:team_rating_snapshot, ratings_config_version: config,
                                                  team_season: create(:team_season, season: game.season))
    prediction = create(:prediction, game:, ratings_config_version: config, home_team_snapshot: home_snapshot,
                                     away_team_snapshot: away_snapshot, home_score: 75, away_score: 70,
                                     home_win_probability: 0.6, pace: 68)
    odd = create(:game_odd, game:, fetched_at: date.noon, spread_point: -5, moneyline_home: 150, total_points: 145)
    %w[spread moneyline total].each do |bet_type|
      create(:bet_recommendation, game:, prediction:, game_odd: odd, ratings_config_version: config, bet_type:, current: true,
                                  recommended: true, team: bet_type == 'total' ? 'over' : 'home',
                                  ev: 0.25, confidence: 0.75, vegas_odds: 150)
    end

    get '/games/betting', params: { date: date.to_s, sort: 'spread', direction: 'asc' }

    region = response.parsed_body.at_css('[role="region"]')
    expect(region.at_css('table')['data-controller']).to eq('betting-sort')
    %w[spread moneyline total].each do |sort|
      expect(region.at_css("a[href='#{betting_games_path(date:, sort:, direction: 'desc')}']")).to be_present
    end
    expect(region.at_css('[data-controller="betting-expand"]')['data-action']).to eq('click->betting-expand#toggle')
    details = region.at_css('tr.expandable-row')
    expect(details['class']).to include('hidden')
    expect(details.text).to include('Predicted Score:', 'Vegas Line:', 'Vegas Odds:', 'Predicted Total:', '75.0%')
    expect(region.text).to include(game.home_team_name, 'Over 145')
  end
end
