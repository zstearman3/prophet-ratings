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
      # Create a GameOdd if one doesn't exist for this game
      unless game.game_odd
        GameOdd.create!(
          game: game,
          fetched_at: Time.current,
          moneyline_away: Faker::Number.between(from: -200, to: 200),
          moneyline_home: Faker::Number.between(from: -200, to: 200),
          spread_away_odds: Faker::Number.between(from: -120, to: 120),
          spread_home_odds: Faker::Number.between(from: -120, to: 120),
          spread_point: Faker::Number.decimal(l_digits: 1, r_digits: 1),
          total_over_odds: Faker::Number.between(from: -120, to: 120),
          total_points: Faker::Number.decimal(l_digits: 2, r_digits: 1),
          total_under_odds: Faker::Number.between(from: -120, to: 120)
        )
      end

      # Create a few BookmakerOdds for each game
      %w[DraftKings FanDuel BetMGM].each do |bookmaker|
        %w[moneyline spread total].each do |market|
          %w[home away].each do |side|
            BookmakerOdd.create!(
              game: game,
              bookmaker: bookmaker,
              fetched_at: Time.current,
              market: market,
              odds: Faker::Number.between(from: -200, to: 200),
              team_name: side == 'home' ? game.home_team.try(:name) : game.away_team.try(:name),
              team_side: side,
              value: Faker::Number.decimal(l_digits: 2, r_digits: 1)
            )
          end
        end
      end
    end

    puts 'Fake odds seeded for all games!'
  end
end
