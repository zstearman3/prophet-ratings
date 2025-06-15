# frozen_string_literal: true

namespace :teams do
  desc 'Import odds API aliases from matches CSV'
  task import_odds_api_aliases: :environment do
    require 'csv'

    csv_path = Rails.root.join('db/data/odds_api_matches.csv')
    created = 0
    skipped = 0

    CSV.foreach(csv_path, headers: true) do |row|
      team_id = row['id']
      alias_value = row['odds_api_name']
      next if team_id.nil? || alias_value.nil?

      team = Team.find_by(id: team_id)
      if team
        # Only create if not already present
        if team.team_aliases.exists?(value: alias_value, source: 'odds-api')
          skipped += 1
        else
          team.team_aliases.create!(value: alias_value, source: 'odds-api')
          puts "Created alias for #{team.school}: #{alias_value}"
          created += 1
        end
      end
    end

    puts "\nCreated #{created} aliases. Skipped #{skipped} existing."
  end
end
