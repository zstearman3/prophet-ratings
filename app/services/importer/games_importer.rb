module Importer
  module GamesImporter
    class << self
      def import(data)
        data.each do |game|
          process_game(game)
        end
      end

      private

      def process_game(game)
        home_team = Team.find_by(school: game[:home_team])
        away_team = Team.find_by(school: game[:away_team])

        puts "Found #{home_team&.school} vs. #{away_team&.school}"
      end
    end
  end
end
