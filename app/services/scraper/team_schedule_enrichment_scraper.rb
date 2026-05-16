# frozen_string_literal: true

module Scraper
  class TeamScheduleEnrichmentScraper < Scraper
    SPORTS_REFERENCE_TIME_ZONE = ActiveSupport::TimeZone['Eastern Time (US & Canada)']

    def initialize(team:, season:)
      @team = team
      @season = season
    end

    def schedule_data
      schedule_rows.filter_map { |row| parse_row(row) }
    end

    private

    attr_reader :team, :season

    def schedule_rows
      sleep(SLEEP_COUNT)

      response = HTTParty.get(schedule_url)
      return [] unless response&.code == 200

      document = Nokogiri::HTML(response.body.to_s)
      document.css('table#schedule tbody tr').reject { |row| row['class'].to_s.split.include?('thead') }
    rescue HTTParty::Error, Timeout::Error => e
      log_schedule_failure('request', e)
      []
    rescue StandardError => e
      log_schedule_failure('parse', e)
      []
    end

    def log_schedule_failure(stage, error)
      Rails.logger.warn("Sports Reference schedule #{stage} failed for #{schedule_url}: #{error.class} - #{error.message}")
    end

    def parse_row(row)
      date_cell = row.at_css("td[data-stat='date_game']")
      opponent_cell = row.at_css("td[data-stat='opp_name']")
      venue_name = row.at_css("td[data-stat='arena']")&.text.to_s.strip
      date = date_from_cell(date_cell)
      opponent_name = opponent_cell&.at_css('a')&.text.to_s.strip
      return if date.blank? || opponent_name.blank?

      {
        date:,
        start_time: start_time_from(row, date),
        opponent_name:,
        game_location: row.at_css("td[data-stat='game_location']")&.text.to_s.strip,
        venue_name:,
        box_score_url: box_score_url_from(date_cell),
        source_url: schedule_url
      }
    end

    def box_score_url_from(date_cell)
      link = date_cell&.at_css('a')
      link&.attribute('href')&.value
    end

    def date_from_cell(cell)
      raw_date = cell&.attribute('csk')&.value
      return if raw_date.blank?

      Date.parse(raw_date)
    rescue ArgumentError
      nil
    end

    def start_time_from(row, date)
      time_text = row.at_css("td[data-stat='time_game']")&.text.to_s.strip
      return date.in_time_zone if time_text.blank?

      cleaned = time_text.downcase.delete('.')
      time_token = cleaned[/\A\d{1,2}:\d{2}(?:\s*[ap]m?)?/]
      return date.in_time_zone if time_token.blank?

      cleaned_time = time_token.delete(' ')
      cleaned_time = "#{cleaned_time}m" if cleaned_time.match?(/\A\d{1,2}:\d{2}[ap]\z/)

      SPORTS_REFERENCE_TIME_ZONE.parse("#{date} #{cleaned_time}")&.in_time_zone || date.in_time_zone
    rescue StandardError
      date.in_time_zone
    end

    def schedule_url
      @schedule_url ||= "#{BASE_URL}/cbb/schools/#{sports_reference_slug}/men/#{season.year}-schedule.html"
    end

    def sports_reference_slug
      match = team.url.to_s.match(%r{/cbb/schools/([^/]+)/men/?})
      return match[1] if match

      team.slug
    end
  end
end
