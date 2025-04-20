# frozen_string_literal: true

module Importer
  module GamesImporter
    class << self
      def import(data)
        data.each do |row|
          process_game(row)
        end
      end

      private

      def find_or_create_team_game(game, team_season, home:)
        return nil unless team_season&.team
      
        TeamGame.find_or_create_by!(
          game: game,
          team: team_season.team,
          team_season: team_season,
          home: home
        )
      end

      def process_team_game(team_game, data, team_season, opponent_team_season)
        return unless team_game

        data[:team_season_id] = team_season&.id
        data[:opponent_team_season_id] = opponent_team_season&.id

        team_game.update(data)
      end

      def process_game(row)
        season = Season.find_by('start_date <= ? AND end_date >= ?', row[:date], row[:date])

        home_team_name = row[:home_team]
        away_team_name = row[:away_team]
        
        home_team = Team.search(home_team_name)
        away_team = Team.search(away_team_name)

        if !home_team || !away_team
          Rails.logger.info("Partial team match: #{home_team_name} vs #{away_team_name} on #{row[:date]}")
        end
                
        home_team_season = home_team ? TeamSeason.find_by(season:, team: home_team) : nil
        away_team_season = away_team ? TeamSeason.find_by(season:, team: away_team) : nil

        game = Game.find_or_initialize_by(
          home_team_name: row[:home_team],
          away_team_name: row[:away_team],
          start_time: row[:date]
        )

        game.update(
          season:,
          home_team_score: row[:home_team_score],
          away_team_score: row[:away_team_score],
          location: row[:location],
          url: row[:url]
        )

        if (home_game = find_or_create_team_game(game, home_team_season, home: true))
          process_team_game(home_game, row[:home_team_stats], home_team_season, away_team_season)
        end
      
        if (away_game = find_or_create_team_game(game, away_team_season, home: false))
          process_team_game(away_game, row[:away_team_stats], away_team_season, home_team_season)
        end

        game.finalize
      end
    end
  end
end
