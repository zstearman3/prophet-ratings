# frozen_string_literal: true

module Importer
  # Report conservative schedule reconciliation while reusing the standard game import writes.
  class ScheduleRowImporter
    def initialize(season:, row:)
      @season = season
      @row = row
    end

    def call
      validate_season
      candidates = matching_games
      if candidates.size > 1 || candidates.any? { |game| game.season_id != season.id }
        return { outcome: 'ambiguous', teams: row.slice(:home_team, :away_team), candidate_ids: candidates.map(&:id) }
      end

      import_game(candidates.first&.attributes || {})
    end

    private

    attr_reader :season, :row, :game, :before

    def validate_season
      date = Game.schedule_date_for(Game.schedule_time_for(row.fetch(:date)))
      return if (season.start_date..season.end_date).cover?(date)

      raise ArgumentError, "Source game outside target season: #{date}"
    end

    def import_game(attributes)
      @before = attributes
      @game = GamesImporter.import_game(row, season:)
      game_report
    end

    def game_report
      { game_id: game.id, outcome:, changes:, unmatched: unmatched_teams, possible_move_ids: possible_moves }
    end

    def changes
      game.attributes.except('created_at', 'updated_at').reject { |key, value| before[key] == value }
    end

    def matching_games
      by_url = url_matches
      by_date = same_date_matches.limit(2).to_a
      (by_url + by_date).uniq(&:id)
    end

    def url_matches
      return [] if placeholder_url?

      Game.where(url: row[:url]).limit(2).to_a
    end

    def placeholder_url?
      row.fetch(:url, '').to_s.match?(%r{\A\s*\z|/cbb/boxscores/index\.cgi})
    end

    def same_date_matches
      date = Game.schedule_date_for(Game.schedule_time_for(row.fetch(:date)))
      scope = Game.on_schedule_date(date).or(Game.where(start_time: Time.zone.local(date.year, date.month, date.day).all_day))
      matches = scope.where(team_names)
      return matches unless row[:neutral] == true || row[:venue_type] == 'neutral'

      matches.or(scope.where(home_team_name: row[:away_team], away_team_name: row[:home_team]))
    end

    def team_names
      { home_team_name: row[:home_team], away_team_name: row[:away_team] }
    end

    def outcome
      return 'created' if before.empty?
      return 'updated' if changes.any?

      before['status'] == 'final' ? 'protected' : 'unchanged'
    end

    def unmatched_teams
      [game.home_team_season ? nil : row[:home_team], game.away_team_season ? nil : row[:away_team]].compact
    end

    def possible_moves
      season.games.scheduled.where(team_names).where.not(id: game.id).pluck(:id)
    end
  end
end
