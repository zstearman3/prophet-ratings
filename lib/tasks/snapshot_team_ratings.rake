namespace :ratings do
  desc "Backfill team rating snapshots for each day of a given season"
  task backfill_ratings: :environment do
    season = Season.current
    start_date = season.start_date

    puts "Backfilling ratings for season: #{season.year}"

    (start_date..season.end_date).each do |date|
      puts "Backfilling for #{date}..."
      games = Game.where(start_time: date.beginning_of_day..date.end_of_day)
      ProphetRatings::OverallRatingsCalculator.new(season)
        .calculate_season_ratings(as_of: date)
      games.each(&:generate_prediction!)
      games.each do |game|
        game.finalize_prediction! if game.final?
      end
    end

    puts "✅ Done backfilling ratings for season #{season.year}"
  end
end
