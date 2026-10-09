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
    version = RatingsConfigVersion.default_version

    puts "Backfilling ratings for season: #{season.year}"
    ProphetRatings::PreseasonInitializer.new(season, ratings_config_version: version).call

    (start_date..season.end_date).each do |date|
      puts "Backfilling for #{date}..."
      games = Game.on_schedule_date(date)
      ProphetRatings::OverallRatingsCalculator.new(season, ratings_config_version: version).call(as_of: date)
      games.each do |game|
        game.generate_prediction!(ratings_config_version: version)
        game.finalize(ratings_config_version: version) if game.final?
      end
    end

    puts "✅ Done backfilling ratings for season #{season.year}"
  end
end
