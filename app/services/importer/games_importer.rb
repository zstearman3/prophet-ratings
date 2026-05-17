# frozen_string_literal: true

module Importer
  # rubocop:disable Metrics/ModuleLength
  module GamesImporter
    TEAM_STAT_KEYS = %i[minutes field_goals_made field_goals_attempted two_pt_made two_pt_attempted three_pt_made
                        three_pt_attempted free_throws_made free_throws_attempted offensive_rebounds
                        defensive_rebounds rebounds assists steals blocks turnovers fouls points].freeze
    BOX_SCORE_HEADER_SOURCE = 'sports_reference_box_score_header'

    class << self
      def import(data) = data.each { |row| process_game(row) }

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

        return process_complete_game(game, row, season, home_team_season, away_team_season) if game_complete?(row)

        process_incomplete_game(game, row, season, home_team_season, away_team_season)
      end

      def process_complete_game(game, row, season, home_team_season, away_team_season)
        attrs = {
          season:,
          start_time: row[:date],
          home_team_score: row[:home_team_score],
          away_team_score: row[:away_team_score],
          url: row[:url]
        }
        attrs.merge!(venue_attributes(row, home_team_season&.team, game)) unless manual_venue?(game)
        game.update!(attrs)

        home_game = find_or_create_team_game(game, home_team_season, home: true)
        away_game = find_or_create_team_game(game, away_team_season, home: false)
        process_team_game(home_game, row[:home_team_stats], home_team_season, away_team_season) if home_game
        process_team_game(away_game, row[:away_team_stats], away_team_season, home_team_season) if away_game

        finalize_game_if_possible(game)
      end

      def process_incomplete_game(game, row, season, home_team_season, away_team_season)
        # Keep unplayed/incomplete games scheduled and avoid clobbering existing finals with partial rows.
        attrs = {
          season:,
          start_time: row[:date],
          url: row[:url],
          home_team_score: game.final? ? game.home_team_score : row[:home_team_score],
          away_team_score: game.final? ? game.away_team_score : row[:away_team_score]
        }
        attrs.merge!(venue_attributes(row, home_team_season&.team, game)) unless manual_venue?(game)
        game.update!(attrs)
        home_game = find_or_create_team_game(game, home_team_season, home: true)
        away_game = find_or_create_team_game(game, away_team_season, home: false)
        process_team_game(home_game, {}, home_team_season, away_team_season)
        process_team_game(away_game, {}, away_team_season, home_team_season)
        game.scheduled! unless game.final? && finalized_game_data_present?(game)
      end

      def finalize_game_if_possible(game)
        game.finalize
      rescue ProphetRatings::GameFinalizer::MissingDerivedStatsError => e
        Rails.logger.warn("Skipping finalization for game #{game.id}: #{e.message}")
        game.scheduled!
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

      def venue_attributes(row, home_team, game)
        explicit_attrs = row.slice(:venue_type, :venue_source, :venue_confidence, :venue_name, :neutral)
        return explicit_attrs if explicit_attrs.values.any?(&:present?) || explicit_attrs.key?(:neutral)
        return {} if venue_data_present?(game)

        box_score_location_attributes(row[:box_score_location], home_team)
      end

      def box_score_location_attributes(box_score_location, home_team)
        venue_name = box_score_location.to_s.strip
        return {} if venue_name.blank?

        attrs = {
          venue_source: BOX_SCORE_HEADER_SOURCE,
          venue_name:
        }
        return attrs unless home_location?(home_team, venue_name)

        attrs.merge(
          venue_type: 'home',
          venue_confidence: 'confirmed',
          neutral: false
        )
      end

      def home_location?(home_team, location)
        return false unless home_team

        exact_match?(location, home_team.home_venue) || location_includes?(location, home_team.location)
      end

      def exact_match?(location, expected)
        expected.present? && location.casecmp(expected.strip).zero?
      end

      def location_includes?(location, expected)
        expected.present? && location.downcase.include?(expected.strip.downcase)
      end

      def venue_data_present?(game)
        !game.venue_unknown? || game.venue_source.present? || game.venue_name.present? || !game.neutral.nil?
      end

      def manual_venue?(game)
        game.venue_confidence == 'manual' || game.venue_source == 'manual_override'
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
