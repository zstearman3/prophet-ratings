# frozen_string_literal: true

module Departures
  # Supported Sidearm overall table, with explicit total columns (never AVG).
  class SidearmTotals
    def initialize(source:, html:, prior_season_year:)
      @source = source
      @document = Nokogiri::HTML(html)
      @prior_season_year = prior_season_year
    end

    def call
      validate_page
      rows = players
      Contract.unique!(rows.pluck('player_source_url'), 'school player identities')
      summarize(rows)
    end

    def self.unique_heading(headings)
      Contract.check!(headings.one?, 'Missing or ambiguous Overall Totals heading')
      headings.first
    end

    def self.table_after(heading)
      table = heading.xpath('following::table[1]').first
      Contract.check!(table.present?, 'Missing overall table')
      table
    end

    def self.values(cells, headers)
      { 'games' => integer(cells[headers.index('GP')]&.text, 'games'),
        'player_points' => integer(cells[headers.index('PTS')]&.text, 'player_points'),
        'player_minutes' => integer(cells[headers.index('MIN')]&.text, 'player_minutes') }
    end

    def self.headers(table)
      headers = table.css('thead tr').last.css('th').map { |cell| cell.text.strip }
      validate_headers(headers)
      headers
    end

    def self.validate_headers(headers)
      Contract.check!(%w[Player GP MIN PTS].all? { |heading| headers.count(heading) == 1 }, 'Unsupported totals columns')
    end

    def self.validate_player_url(uri, source_uri)
      Contract.check!(uri.host == source_uri.host && uri.path.include?('/roster/'), 'Unsupported school player identity')
    end

    def self.integer(text, name, minimum: 0)
      value = text.to_s.strip
      Contract.check!(value.match?(/\A(?:\d+|\d{1,3}(?:,\d{3})+)\z/), "Invalid total #{name}")
      Contract.integer!(Integer(value.delete(','), 10), name, minimum:)
    end

    private

    attr_reader :source, :document, :prior_season_year

    def validate_page
      season = "#{prior_season_year - 1}-#{prior_season_year.to_s.last(2)}"
      Contract.check!(document.css('h1,h2,h3').any? { |node| node.text.strip == "#{season} Men's Basketball Cumulative Statistics" },
                      'Unsupported school season/title')
      Contract.check!(source.fetch('scope') == Contract::SCOPE && source.fetch('scope_evidence').present?,
                      'Review final overall scope including postseason/excluding exhibitions')
    end

    def players
      table = overall_table
      headers = self.class.headers(table)
      table.css('tbody tr').filter_map { |row| player(row, headers) }
    end

    def summarize(rows)
      denominator = team_points
      Contract.check!(rows.any? && rows.pluck('player_points').sum == denominator, 'Player totals disagree with team points')
      { 'source_id' => source.fetch('id'), 'team_name_source' => source.fetch('team_name_source'),
        'team_points' => denominator, 'team_minutes' => rows.pluck('player_minutes').sum, 'players' => rows }
    end

    def overall_table
      headings = document.css('h2,h3').select { |node| node.text.strip == 'Overall Totals' }
      parser = self.class
      parser.table_after(parser.unique_heading(headings))
    end

    def team_points
      totals = document.css('table tr').select { |row| row.css('th,td').first&.text&.strip == 'Total Points' }
      Contract.check!(totals.one?, 'Missing or ambiguous team points')
      self.class.integer(totals.first.css('th,td')[1]&.text, 'team_points', minimum: 1)
    end

    def player(row, headers)
      cells = row.css('th,td')
      link = cells[headers.index('Player')]&.at_css('a[href]')
      return unless link

      self.class.values(cells, headers).merge('player_name_source' => link.text.strip, 'player_source_url' => player_url(link['href']))
    end

    def player_url(href)
      source_url = source.fetch('url')
      uri = URI.join(source_url, href)
      self.class.validate_player_url(uri, URI.parse(source_url))
      Contract.url!(uri.to_s)
    end
  end
end
