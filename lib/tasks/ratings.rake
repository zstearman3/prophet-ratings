# frozen_string_literal: true

namespace :ratings do
  desc 'Backfill team rating snapshots for each day of the current season'
  task backfill: :environment do
    season = Season.current
    backfill_for_season(season)
  end

  desc 'Backfill team rating snapshots for all seasons'
  task backfill_all: :environment do
    Season.order(year: :asc).each do |season|
      backfill_for_season(season)
    end
  end

  def backfill_for_season(season)
    start_date = season.start_date

    puts "Backfilling ratings for season: #{season.year}"
    ProphetRatings::PreseasonInitializer.new(season).call

    (start_date..season.end_date).each do |date|
      puts "Backfilling for #{date}..."
      games = Game.where(start_time: date.all_day)
      ProphetRatings::OverallRatingsCalculator.new(season).call(as_of: date)
      games.each(&:generate_prediction!)
      games.each { |game| game.finalize if game.final? }
    end

    puts "✅ Done backfilling ratings for season #{season.year}"
  end
end
