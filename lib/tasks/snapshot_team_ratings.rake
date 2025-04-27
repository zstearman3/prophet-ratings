namespace :ratings do
  desc "Backfill team rating snapshots for each day of a given season"
  task backfill_ratings: :environment do
    season = Season.current
    start_date = season.start_date + 21.days

    puts "Backfilling ratings for season: #{season.year}"

    (start_date..season.end_date).each do |date|
      puts "Backfilling for #{date}..."
      ProphetRatings::OverallRatingsCalculator.new(season)
        .calculate_season_ratings(as_of: date)
    end

    puts "✅ Done backfilling ratings for season #{season.year}"
  end
end
