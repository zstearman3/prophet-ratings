# frozen_string_literal: true

module Importer
  module GamesImporter
    TEAM_STAT_KEYS = %i[minutes field_goals_made field_goals_attempted two_pt_made two_pt_attempted three_pt_made
                        three_pt_attempted free_throws_made free_throws_attempted offensive_rebounds
                        defensive_rebounds rebounds assists steals blocks turnovers fouls points].freeze

    class << self
      def import(data)
        data.each do |row|
          process_game(row)
        end
      end

      private

      def find_game_by_teams_and_date(home_team_name, away_team_name, date)
        Game.where(home_team_name:, away_team_name:)
            .where('DATE(start_time) = ?', date)
            .first
      end

      def find_or_create_team_game(game, team_season, home:)
        return nil unless team_season&.team

        TeamGame.find_or_create_by!(
          game:,
          team: team_season.team,
          team_season:,
          home:
        )
      end

      def process_team_game(team_game, data, team_season, opponent_team_season)
        return unless team_game

        attrs = (data || {}).dup
        attrs[:team_season_id] = team_season&.id
        attrs[:opponent_team_season_id] = opponent_team_season&.id

        team_game.update!(attrs)
      end

      def process_game(row)
        season = Season.find_by('start_date <= ? AND end_date >= ?', row[:date], row[:date])

        home_team_name = row[:home_team]
        away_team_name = row[:away_team]

        home_team = Team.search(home_team_name)
        away_team = Team.search(away_team_name)

        Rails.logger.info("Partial team match: #{home_team_name} vs #{away_team_name} on #{row[:date]}") if !home_team || !away_team

        home_team_season = home_team ? TeamSeason.find_by(season:, team: home_team) : nil
        away_team_season = away_team ? TeamSeason.find_by(season:, team: away_team) : nil

        date = row[:date].to_date
        game = find_game_by_teams_and_date(row[:home_team], row[:away_team], date) ||
               Game.new(home_team_name: row[:home_team], away_team_name: row[:away_team], start_time: row[:date])

        if game_complete?(row)
          game.update!(
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
          return
        end

        # Keep unplayed/incomplete games scheduled and avoid clobbering existing finals with partial rows.
        game.update!(
          season:,
          location: row[:location],
          url: row[:url],
          home_team_score: game.final? ? game.home_team_score : row[:home_team_score],
          away_team_score: game.final? ? game.away_team_score : row[:away_team_score]
        )
        game.scheduled! unless game.final? && finalized_game_data_present?(game)
      end

      def game_complete?(row)
        score_present?(row[:home_team_score]) &&
          score_present?(row[:away_team_score]) &&
          team_stats_complete?(row[:home_team_stats]) &&
          team_stats_complete?(row[:away_team_stats])
      end

      def score_present?(score)
        score.to_s.strip.present?
      end

      def team_stats_complete?(stats)
        return false unless stats.respond_to?(:[])

        TEAM_STAT_KEYS.all? do |key|
          stats[key].to_s.strip.present? || stats[key.to_s].to_s.strip.present?
        end
      end

      def finalized_game_data_present?(game)
        score_present?(game.home_team_score) &&
          score_present?(game.away_team_score) &&
          game.minutes.to_i.positive? &&
          game.possessions.present?
      end
    end
  end
end
