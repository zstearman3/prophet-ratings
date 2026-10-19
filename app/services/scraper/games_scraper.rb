# frozen_string_literal: true

module Scraper
  class GamesScraper < Scraper
    # A failed request or unsupported page must never count as an empty schedule.
    class SourceError < StandardError; end

    def initialize(date = Game.current_schedule_date)
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
      document = schedule_document

      urls = document.css('div.game_summaries div.gender-m').filter_map do |game_div|
        parse_game_entry(game_div)
      end

      @game_urls = urls
    end

    def schedule_document
      sleep(SLEEP_COUNT)
      response = HTTParty.get(schedule_url(@date))
      document = successful_document(response)
      raise SourceError, "Unrecognized or unavailable schedule page for #{@date}" unless document.at_css('div.game_summaries')

      document
    end

    def successful_document(response)
      validate_response(response)

      Nokogiri::HTML(response.body)
    end

    def validate_response(response)
      raise_source_error(response) unless response.success?
    end

    def raise_source_error(response)
      raise SourceError, "Request failed for #{@date}: HTTP #{response.code}"
    end

    def game_urls
      @game_urls ||= set_game_urls
    end

    def game_urls_for_team!(team)
      document = schedule_document
      aliases = team.team_aliases.pluck(:value)
      all_names = [team.school] + aliases

      urls = document.css('div.game_summaries div.gender-m').filter_map do |game_div|
        team_names = game_rows(game_div).filter_map { |row| team_name_from_row(row) }

        # A known team is enough; its opponent need not be tracked.
        next unless team_names.any? { |name| all_names.include?(name) }

        parse_game_entry(game_div)
      end

      @game_urls = urls
    end

    def parse_game_entry(game_div)
      schedule_entry = parse_scheduled_game(game_div)
      gamelink = game_div.at_css('td.gamelink a')&.attribute('href')&.value
      return gamelink if gamelink.present?

      schedule_entry
    end

    def parse_scheduled_game(game_div)
      reject_nonfinal_status!(game_div.css('table.teams td:nth-child(3)'))
      rows = game_rows(game_div)
      raise SourceError, "Contradictory schedule outcome for #{@date}" if rows.any? { |row| row.matches?('.winner.loser') }

      source_completion_evidence = schedule_completion_evidence(game_div, rows)

      away_row = rows[0]
      home_row = rows[1]
      home_team = team_name_from_row(home_row)
      away_team = team_name_from_row(away_row)
      raise SourceError, "Missing scheduled teams for #{@date}" if home_team.blank? || away_team.blank?

      {
        home_team:,
        away_team:,
        home_team_score: score_from_row(home_row),
        away_team_score: score_from_row(away_row),
        date: scheduled_start_time(time_from_rows(rows)),
        away_team_stats: {},
        home_team_stats: {},
        source_completed: source_completion_evidence.present?,
        source_completion_evidence:,
        url: schedule_url(@date)
      }
    end

    def game_rows(game_div)
      rows = game_div.css('table.teams tr').select { |row| row.css('td').size == 3 && !row.at_css('td[colspan]') }
      raise SourceError, "Malformed scheduled game for #{@date}" unless rows.size == 2

      rows
    end

    def team_name_from_row(row)
      node = row&.at_css('td:first-child, strong')
      return '' unless node

      copy = node.dup
      copy.css('.pollrank').remove
      copy.text.squish
    end

    def reject_nonfinal_status!(status_nodes)
      status = status_nodes.xpath('.//text()').map(&:text).join(' ')
      nonfinal = /\b(cancell?ed|postponed|suspended|abandoned|live|in[[:space:]-]+progress|halftime|scheduled|[12](?:st|nd) half)\b/i
      return unless status.match?(nonfinal)

      raise SourceError, "Nonfinal source status for #{@date}: #{status.squish}"
    end

    def schedule_completion_evidence(game_div, rows)
      evidence = winner_loser_evidence(rows)
      evidence = final_schedule_evidence(game_div, rows) || evidence
      validate_final_scores!(*rows.map { |row| score_from_row(row) }) if evidence
      evidence
    end

    def final_schedule_evidence(game_div, rows)
      return unless game_div.css('td.gamelink').text.squish.match?(/\AFinal(?:\s|\z)/i)

      validate_winner_loser!(rows) if rows.any? { |row| row.matches?('.winner, .loser') }
      'schedule_final'
    end

    def winner_loser_evidence(rows)
      return unless rows.any? { |row| row.matches?('.winner') }

      validate_winner_loser!(rows)
      'schedule_winner_loser'
    end

    def validate_winner_loser!(rows)
      winners, other_rows = rows.partition { |row| row.matches?('.winner') }
      loser = other_rows.first
      raise SourceError, "Contradictory schedule outcome for #{@date}" unless winners.one? && other_rows.one? && loser.matches?('.loser')

      validate_winner!(score_from_row(winners.first), score_from_row(loser))
    end

    def validate_winner!(winner_score, loser_score)
      validate_final_scores!(winner_score, loser_score)
      raise SourceError, "Inconsistent schedule winner for #{@date}" if winner_score <= loser_score
    end

    def validate_final_scores!(away_score, home_score)
      return if away_score.is_a?(Integer) && home_score.is_a?(Integer) && away_score != home_score

      raise SourceError, "Invalid final scores for #{@date}"
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

      parsed_time = Game::SCHEDULE_TIME_ZONE.parse("#{@date} #{cleaned_time}")
      parsed_time&.in_time_zone || fallback_start_time
    rescue StandardError
      fallback_start_time
    end

    def completed_start_time(date_text)
      return fallback_start_time if date_text.blank?

      parsed_time = Game::SCHEDULE_TIME_ZONE.parse(date_text)
      parsed_time&.in_time_zone || fallback_start_time
    rescue StandardError
      fallback_start_time
    end

    def fallback_start_time
      Game.schedule_time_for(@date)
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
      raise SourceError, "Boxscore request failed: HTTP #{response.code}" unless response.success?

      document = Nokogiri::HTML(response.body)
      unless url.match?(%r{\A/cbb/boxscores/\d{4}-\d{2}-\d{2}-[^/]+\.html\z}) && document.at_css('div.scorebox')
        raise SourceError, "Unrecognized boxscore page: #{url}"
      end

      team_boxes = document.css('div.scorebox > div').select { |box| box.at_css('strong') }
      home_team = team_name_from_row(team_boxes[1])
      away_team = team_name_from_row(team_boxes[0])
      raise SourceError, "Missing boxscore teams: #{url}" if home_team.blank? || away_team.blank?

      raise SourceError, "Unrecognized boxscore context: #{url}" unless document.at_css('div.scorebox_meta') && team_boxes.size == 2

      reject_nonfinal_status!(document.css('.scorebox_meta, .scorebox .status'))
      home_team_score = parsed_score(team_boxes[1]&.css('div.score')&.text)
      away_team_score = parsed_score(team_boxes[0]&.css('div.score')&.text)
      validate_final_scores!(away_team_score, home_team_score)
      date = completed_start_time(document.css('div.scorebox_meta div')[0]&.text)
      box_score_location = document.css('div.scorebox_meta div')[1]&.text.to_s.strip
      away_team_stats = team_stats(document, team_boxes[0])
      home_team_stats = team_stats(document, team_boxes[1])

      {
        home_team:,
        away_team:,
        home_team_score:,
        away_team_score:,
        date:,
        box_score_location:,
        away_team_stats:,
        home_team_stats:,
        source_completed: true,
        source_completion_evidence: 'boxscore',
        url:
      }
    end

    def team_stats(document, team_box)
      team_url = team_box.at_css('strong a')&.[]('href').to_s
      slug = team_url[%r{\A/cbb/schools/([a-z0-9-]+)/}, 1]
      return {} unless slug

      parse_team_stats(document.at_xpath("//table[@id='box-score-basic-#{slug}']/tfoot/tr"))
    end

    def scrape_day
      game_urls.map { |entry| scrape_entry(entry) }
    end

    def scrape_day_batch(start_at, batch_size)
      batch_urls = game_urls
      batch_urls = batch_urls.slice(start_at, batch_size) || []

      batch_urls.map { |entry| scrape_entry(entry) }
    end

    def scrape_entry(entry)
      return entry if entry.is_a?(Hash)

      scrape_game(entry)
    end
  end
end
