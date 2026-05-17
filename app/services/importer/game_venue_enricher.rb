# frozen_string_literal: true

module Importer
  class GameVenueEnricher
    MANUAL_SOURCE = 'manual_override'
    SPORTS_REFERENCE_TEAM_SCHEDULE_SOURCE = 'sports_reference_team_schedule'

    def initialize(games = Game.all, overwrite_manual: false)
      @games = games
      @overwrite_manual = overwrite_manual
    end

    def call
      records.each { |game| enrich_game(game) }
    end

    private

    attr_reader :games, :overwrite_manual

    def records
      games.respond_to?(:find_each) ? games.find_each : Array(games)
    end

    def enrich_game(game)
      return if manual_classification?(game) && !overwrite_manual

      attrs = schedule_attributes(game)
      game.update!(attrs) if attrs.present?
    end

    def schedule_attributes(game)
      match = schedule_row_for(game)
      return unless match

      row, team = match
      venue_type = schedule_venue_type(row, team, game)
      return if venue_type == 'unknown'

      venue_attributes(venue_type, row[:venue_name])
    end

    def schedule_venue_type(row, team, game)
      case row[:game_location].to_s.strip
      when 'N'
        'neutral'
      when '@'
        team == game.away_team ? 'home' : 'unknown'
      else
        team == game.home_team ? 'home' : 'unknown'
      end
    end

    def venue_attributes(venue_type, venue_name)
      {
        venue_type:,
        venue_source: SPORTS_REFERENCE_TEAM_SCHEDULE_SOURCE,
        venue_confidence: 'confirmed',
        venue_name:,
        neutral: venue_type == 'neutral'
      }
    end

    def schedule_row_for(game)
      [game.home_team, game.away_team].compact.each do |team|
        rows = begin
          schedule_rows_for(team, game.season)
        rescue StandardError => e
          Rails.logger.warn("Unable to scrape venue schedule for team_id=#{team.id}, season_id=#{game.season_id}: #{e.message}")
          next
        end

        row = rows.find { |candidate| schedule_row_matches_game?(candidate, game) }
        return [row, team] if row
      end

      nil
    end

    def schedule_rows_for(team, season)
      schedule_cache[[team.id, season.id]] ||= Scraper::TeamScheduleEnrichmentScraper.new(team:, season:).schedule_data
    end

    def schedule_cache
      @schedule_cache ||= {}
    end

    def schedule_row_matches_game?(row, game)
      row[:date] == game.schedule_date &&
        [game.home_team_name, game.away_team_name].map(&:downcase).include?(row[:opponent_name].to_s.downcase)
    end

    def manual_classification?(game)
      game.venue_source == MANUAL_SOURCE || game.venue_confidence == 'manual'
    end
  end
end
