# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Betting table sorting' do
  let(:season) { create(:season, :current) }
  let(:config) { create(:ratings_config_version, current: true) }
  let(:start_time) { 1.day.from_now }
  let(:snapshots) do
    create_list(:team_season, 2, season:).map do |participant|
      create(:team_rating_snapshot, team_season: participant, ratings_config_version: config)
    end
  end
  let!(:game) { create_sort_game('Medium EV', 0.06) }

  it 'starts each market at highest EV, toggles that market, and resets when switching markets' do
    high = create_sort_game('High EV', 0.2)
    low = create_sort_game('No play', -0.02)
    missing = create(:game, season:, start_time:, home_team_name: 'Missing recommendation')

    %w[Spread Moneyline Total].each do |market|
      get '/games/betting', params: { date: game.schedule_date.to_s }
      get sort_link(market)

      aggregate_failures("#{market} first click") do
        expect(response.parsed_body.css('tbody tr[data-betting-sort-target] a').pluck('href'))
          .to eq([high, game, low, missing].map { |record| "/games/#{record.id}" })
        expect_sort_directions(market, 'asc')
      end

      get sort_link(market)
      aggregate_failures("#{market} second click") do
        expect(response.parsed_body.css('tbody tr[data-betting-sort-target] a').pluck('href'))
          .to eq([missing, low, game, high].map { |record| "/games/#{record.id}" })
        expect_sort_directions(market, 'desc')
      end
    end
  end

  def create_sort_game(name, expected_value)
    record = create(:game, season:, start_time:, home_team_name: name)
    snapshots.each_with_index do |snapshot, index|
      create(:team_game, game: record, team: snapshot.team, team_season: snapshot.team_season, home: index.zero?)
    end
    forecast = create(:prediction, game: record, ratings_config_version: config,
                                   home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last,
                                   home_score: 81, away_score: 80, pace: 70)
    prices = create(:game_odd, game: record, fetched_at: Time.current, spread_point: -6.5,
                               moneyline_home: -180, moneyline_away: 150, total_points: 170.5)
    %w[spread moneyline total].each do |bet_type|
      create(:bet_recommendation, game: record, prediction: forecast, game_odd: prices, ratings_config_version: config,
                                  bet_type:, current: true, ev: expected_value, recommended: expected_value.positive?)
    end
    record
  end

  def sort_link(market)
    response.parsed_body.css('thead a').find { |link| link.text == market }['href']
  end

  def expect_sort_directions(active_market, next_direction)
    %w[Spread Moneyline Total].each do |market|
      query = Rack::Utils.parse_query(URI.parse(sort_link(market)).query)
      expect(query).to include('sort' => market.downcase, 'date' => game.schedule_date.to_s,
                               'direction' => market == active_market ? next_direction : 'desc')
    end
  end
end
