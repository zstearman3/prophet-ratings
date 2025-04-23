namespace :ratings do
  desc "Backfill team rating snapshots for each day of a given season"
  task backfill_snapshots: :environment do
    season = Season.current
    first_snapshot_date = season.start_date + 21.days

    puts "Backfilling snapshots for season: #{season.year}"

    (first_snapshot_date..season.end_date).each do |date|
      puts "Snapshotting for #{date}..."
      ProphetRatings::TeamRatingSnapshotService.new(
        season: season,
        as_of: date,
        config_bundle_name: "default"
      ).call
    end

    puts "✅ Done snapshotting for season #{season.year}"
  end
end
