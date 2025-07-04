# frozen_string_literal: true

# lib/tasks/seed_fake_odds.rake
# WARNING: This task is for LOCAL DEVELOPMENT ONLY. DO NOT RUN IN PRODUCTION.
# It seeds fake odds for all existing games.

namespace :fake_odds do
  desc 'Seed fake GameOdd and BookmakerOdd records for existing games (local development only)'
  task seed: :environment do
    unless Rails.env.development?
      puts 'This task is for development only! Aborting.'
      exit 1
    end

    require 'faker'

    Game.find_each do |game|
      game_odd = GameOdd.find_or_initialize_by(game:)
      home_moneyline = Faker::Number.between(from: -50, to: 50) * 10
      away_moneyline = -home_moneyline
      spread_home_odds = Faker::Number.between(from: -12, to: -10) * 10
      spread_away_odds = spread_home_odds
      total_points = Faker::Number.between(from: 100, to: 200)
      total_over_odds = Faker::Number.between(from: -12, to: -10) * 10
      total_under_odds = total_over_odds

      game_odd.fetched_at = Time.current
      game_odd.moneyline_away = away_moneyline
      game_odd.moneyline_home = home_moneyline
      game_odd.spread_away_odds = spread_away_odds
      game_odd.spread_home_odds = spread_home_odds
      game_odd.spread_point = Faker::Number.decimal(l_digits: 1, r_digits: 1)
      game_odd.total_over_odds = total_over_odds
      game_odd.total_points = total_points
      game_odd.total_under_odds = total_under_odds
      game_odd.save!

      # Create a few BookmakerOdds for each game
      %w[DraftKings FanDuel BetMGM].each do |bookmaker|
        %w[moneyline spread total].each do |market|
          %w[home away].each do |side|
            BookmakerOdd.find_or_initialize_by(game:, bookmaker:, market:) do |bookmaker_odd|
              bookmaker_odd.team_name = side == 'home' ? game.home_team.try(:name) : game.away_team.try(:name)
              bookmaker_odd.team_side = side
              bookmaker_odd.fetched_at = Time.current
              bookmaker_odd.odds = Faker::Number.between(from: -200, to: 200)
              bookmaker_odd.value = Faker::Number.decimal(l_digits: 2, r_digits: 1)
              bookmaker_odd.save!
            end
          end
        end
      end
    end

    puts 'Fake odds seeded for all games!'
  end
end
