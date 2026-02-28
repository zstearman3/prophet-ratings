# frozen_string_literal: true

module Scraper
  class GamesScraper < Scraper
    def initialize(date = Time.zone.today)
      @date = date
    end

    def to_json(*_args)
      scrape_day
    end

    def to_json_in_batches(start_at = 0, batch_size = 10)
      scrape_day_batch(start_at, batch_size)
    end

    def to_json_for_team(team)
      game_urls_for_team!(team)
      scrape_day
    end

    def game_count
      sleep(SLEEP_COUNT)

      response = HTTParty.get(schedule_url(@date))
      Nokogiri::HTML(response.body)

      game_urls.size
    end

    private

    def schedule_url(date)
      "#{BASE_URL}/cbb/boxscores/index.cgi?month=#{date.strftime('%-m')}" \
        "&day=#{date.strftime('%-d')}&year=#{date.strftime('%Y')}"
    end

    def game_url(url)
      BASE_URL + url
    end

    def set_game_urls
      response = HTTParty.get(schedule_url(@date))
      document = Nokogiri::HTML(response.body)

      urls = document.css('div.game_summaries div.gender-m').filter_map do |game_div|
        parse_game_entry(game_div)
      end

      @game_urls = urls
    end

    def game_urls
      @game_urls ||= set_game_urls
    end

    def game_urls_for_team!(team)
      sleep(SLEEP_COUNT)

      response = HTTParty.get(schedule_url(@date))
      document = Nokogiri::HTML(response.body)
      aliases = team.team_aliases.pluck(:value)
      all_names = [team.school] + aliases

      urls = document.css('div.game_summaries div.gender-m').filter_map do |game_div|
        team_names = game_rows(game_div).filter_map { |row| team_name_from_row(row) }

        # Only keep games where both teams are matched in the database
        next unless team_names.any? { |name| all_names.include?(name) }

        parse_game_entry(game_div)
      end

      @game_urls = urls
    end

    def parse_game_entry(game_div)
      gamelink = game_div.at_css('td.gamelink a')&.attribute('href')&.value
      return gamelink if gamelink.present?

      parse_scheduled_game(game_div)
    end

    def parse_scheduled_game(game_div)
      rows = game_rows(game_div)
      return nil unless rows.size >= 2

      away_row = rows[0]
      home_row = rows[1]
      home_team = team_name_from_row(home_row)
      away_team = team_name_from_row(away_row)
      return nil if home_team.blank? || away_team.blank?

      {
        home_team:,
        away_team:,
        home_team_score: score_from_row(home_row),
        away_team_score: score_from_row(away_row),
        date: scheduled_start_time(time_from_rows(rows)),
        location: nil,
        away_team_stats: {},
        home_team_stats: {},
        url: schedule_url(@date)
      }
    end

    def game_rows(game_div)
      game_div.css('table.teams tr').select { |row| row.at_css('td:first-child a').present? }
    end

    def team_name_from_row(row)
      return nil unless row

      row.at_css('td:first-child a')&.text.to_s.strip
    end

    def score_from_row(row)
      return nil unless row

      parsed_score(row.css('td')[1]&.text)
    end

    def parsed_score(score_text)
      score = score_text.to_s.strip
      return nil unless score.match?(/\A\d+\z/)

      score.to_i
    end

    def time_from_rows(rows)
      rows.filter_map { |row| row.css('td')[2]&.text.to_s.strip.presence }.first
    end

    def scheduled_start_time(time_text)
      return fallback_start_time if time_text.blank?

      cleaned = time_text.strip.downcase.delete('.')
      time_token = cleaned[/\A\d{1,2}:\d{2}(?:\s*[ap]m?)?/]
      return fallback_start_time if time_token.blank?

      cleaned_time = time_token.delete(' ')
      cleaned_time = "#{cleaned_time}m" if cleaned_time.match?(/\A\d{1,2}:\d{2}[ap]\z/)

      parsed_time = Time.zone.parse("#{@date} #{cleaned_time}")
      parsed_time || fallback_start_time
    rescue StandardError
      fallback_start_time
    end

    def completed_start_time(date_text)
      return fallback_start_time if date_text.blank?

      parsed_time = Time.zone.parse(date_text)
      parsed_time || fallback_start_time
    rescue StandardError
      fallback_start_time
    end

    def fallback_start_time
      @date.in_time_zone
    end

    def parse_team_stats(row)
      return {} unless row

      {
        minutes: row.css("td[data-stat='mp']")&.text,
        field_goals_made: row.css("td[data-stat='fg']")&.text,
        field_goals_attempted: row.css("td[data-stat='fga']")&.text,
        two_pt_made: row.css("td[data-stat='fg2']")&.text,
        two_pt_attempted: row.css("td[data-stat='fg2a']")&.text,
        three_pt_made: row.css("td[data-stat='fg3']")&.text,
        three_pt_attempted: row.css("td[data-stat='fg3a']")&.text,
        free_throws_made: row.css("td[data-stat='ft']")&.text,
        free_throws_attempted: row.css("td[data-stat='fta']")&.text,
        offensive_rebounds: row.css("td[data-stat='orb']")&.text,
        defensive_rebounds: row.css("td[data-stat='drb']")&.text,
        rebounds: row.css("td[data-stat='trb']")&.text,
        assists: row.css("td[data-stat='ast']")&.text,
        steals: row.css("td[data-stat='stl']")&.text,
        blocks: row.css("td[data-stat='blk']")&.text,
        turnovers: row.css("td[data-stat='tov']")&.text,
        fouls: row.css("td[data-stat='pf']")&.text,
        points: row.css("td[data-stat='pts']")&.text
      }
    end

    def scrape_game(url)
      # To comply with sports reference TOS
      sleep(SLEEP_COUNT)

      response = HTTParty.get(game_url(url))
      document = Nokogiri::HTML(response.body)

      team_boxes = document.css('div.scorebox')&.xpath('./div')
      home_team = team_boxes[1]&.css('strong a')&.text
      away_team = team_boxes[0]&.css('strong a')&.text
      home_team_score = parsed_score(team_boxes[1]&.css('div.score')&.text)
      away_team_score = parsed_score(team_boxes[0]&.css('div.score')&.text)
      date = completed_start_time(document.css('div.scorebox_meta div')[0]&.text)
      location = document.css('div.scorebox_meta div')[1]&.text
      away_team_line = document.css('table.stats_table tfoot tr')[0]
      home_team_line = document.css('table.stats_table tfoot tr')[2]

      {
        home_team:,
        away_team:,
        home_team_score:,
        away_team_score:,
        date:,
        location:,
        away_team_stats: parse_team_stats(away_team_line),
        home_team_stats: parse_team_stats(home_team_line),
        url:
      }
    end

    def scrape_day
      game_urls.map { |entry| scrape_entry(entry) }
    end

    def scrape_day_batch(start_at, batch_size)
      batch_urls = game_urls
      end_at = start_at + batch_size

      batch_urls = batch_urls[start_at..end_at]

      batch_urls.map { |entry| scrape_entry(entry) }
    end

    def scrape_entry(entry)
      return entry if entry.is_a?(Hash)

      scrape_game(entry)
    end
  end
end
