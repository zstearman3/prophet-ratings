module Importer
  module GamesImporter
    class << self
      def import(data)
        data.each do |row|
          process_game(row)
        end
      end

      private

      def process_team_game(team_game, data)
        return unless team_game

        team_game.update(data)
      end

      def process_game(row)
        home_team = Team.find_by(school: row[:home_team])
        away_team = Team.find_by(school: row[:away_team])
        season = Season.find_by("start_date <= ? AND end_date >= ?", row[:date], row[:date])

        game = Game.find_or_initialize_by(
          home_team_name: row[:home_team],
          away_team_name: row[:away_team],
          start_time: row[:date],
        )
        
        game.update(
          home_team: home_team,
          away_team: away_team,
          season: season,
          home_team_score: row[:home_team_score],
          away_team_score: row[:away_team_score],
          location: row[:location],
          url: row[:url],
        )

        process_team_game(game.home_team_game, row[:home_team_stats])
        process_team_game(game.away_team_game, row[:away_team_stats])

        game.finalize
      end
    end
  end
end
