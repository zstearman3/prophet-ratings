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

      def process_team_game(team_game, data, team_season)
        return unless team_game

        data[:team_season_id] = team_season&.id

        team_game.update(data)
      end

      def process_game(row)
        home_team = Team.search(row[:home_team]).first
        away_team = Team.search(row[:away_team]).first
        season = Season.find_by('start_date <= ? AND end_date >= ?', row[:date], row[:date])
        home_team_season = TeamSeason.find_by(season:, team: home_team)
        away_team_season = TeamSeason.find_by(season:, team: away_team)

        game = Game.find_or_initialize_by(
          home_team_name: row[:home_team],
          away_team_name: row[:away_team],
          start_time: row[:date]
        )

        game.update(
          home_team:,
          away_team:,
          season:,
          home_team_score: row[:home_team_score],
          away_team_score: row[:away_team_score],
          location: row[:location],
          url: row[:url]
        )

        process_team_game(game.home_team_game, row[:home_team_stats], home_team_season)
        process_team_game(game.away_team_game, row[:away_team_stats], away_team_season)

        game.finalize
      end
    end
  end
end
