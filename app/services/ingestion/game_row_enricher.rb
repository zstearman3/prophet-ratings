# frozen_string_literal: true

module Ingestion
  class GameRowEnricher
    SPORTS_REFERENCE_TEAM_SCHEDULE_SOURCE = 'sports_reference_team_schedule'

    def initialize(rows = [])
      @rows = rows
    end

    def call(rows = @rows)
      rows.map { |row| enrich_row(row) }
    end

    private

    def enrich_row(row)
      venue_row = venue_row_for(row)
      return row unless venue_row

      row.merge(venue_attributes(venue_row))
    end

    def venue_attributes(venue_row)
      venue_type = venue_row[:game_location].to_s.strip == 'N' ? 'neutral' : 'home'
      {
        venue_type:,
        venue_source: SPORTS_REFERENCE_TEAM_SCHEDULE_SOURCE,
        venue_confidence: 'confirmed',
        venue_name: venue_row[:venue_name],
        date: venue_row[:start_time],
        neutral: venue_type == 'neutral'
      }.compact
    end

    def venue_row_for(row)
      teams_for(row).each do |team|
        matched_row = schedule_rows_for(team, season_for(row)).find { |schedule_row| schedule_row_matches_game?(schedule_row, row) }
        return matched_row if matched_row
      rescue StandardError => e
        Rails.logger.warn("Unable to enrich venue row for team_id=#{team.id}: #{e.message}")
      end

      nil
    end

    def schedule_row_matches_game?(schedule_row, game_row)
      box_score_url_matches?(schedule_row, game_row) ||
        (schedule_row[:date] == game_row[:date].to_date && opponent_matches?(schedule_row, game_row))
    end

    def box_score_url_matches?(schedule_row, game_row)
      schedule_row[:box_score_url].present? && schedule_row[:box_score_url] == game_row[:url]
    end

    def opponent_matches?(schedule_row, game_row)
      row_teams = [game_row[:home_team], game_row[:away_team]].map { |team| team.to_s.downcase }
      row_teams.include?(schedule_row[:opponent_name].to_s.downcase)
    end

    def teams_for(row)
      [Team.search(row[:home_team]), Team.search(row[:away_team])].compact
    end

    def season_for(row)
      Season.find_by('start_date <= ? AND end_date >= ?', row[:date], row[:date])
    end

    def schedule_rows_for(team, season)
      schedule_cache[[team.id, season.id]] ||= Scraper::TeamScheduleEnrichmentScraper.new(team:, season:).to_json
    end

    def schedule_cache
      @schedule_cache ||= {}
    end
  end
end
