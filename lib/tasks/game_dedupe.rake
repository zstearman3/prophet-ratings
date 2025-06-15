namespace :games do
  desc 'Deduplicate games by home_team_name, away_team_name, and start_time::date, deleting duplicates and their associations.'
  task dedupe: :environment do
    require 'active_record'

    grouped = Game.all.group_by { |g| [g.home_team_name, g.away_team_name, g.start_time.to_date] }
    dup_groups = grouped.select { |_k, games| games.size > 1 }
    puts "Found \\#{dup_groups.size} duplicate groups."
    dup_groups.each do |key, games|
      keep = games.min_by(&:id)
      dups = games - [keep]
      next if dups.empty?

      puts "Keeping game id=\\#{keep.id} (\\#{key.inspect}), deleting duplicates: \\#{dups.map(&:id).join(', ')}"
      dups.each do |dup|
        TeamGame.where(game_id: dup.id).delete_all
        GameOdd.where(game_id: dup.id).delete_all if defined?(GameOdd)
        BookmakerOdd.where(game_id: dup.id).delete_all if defined?(BookmakerOdd)
        # Add any other associations here as needed
        dup.destroy
      end
    end
    puts 'Deduplication complete.'
  end
end
