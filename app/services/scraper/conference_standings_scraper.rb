# frozen_string_literal: true

module Scraper
  # Reads season membership identities without persisting domain records.
  class ConferenceStandingsScraper < Scraper
    # Source failures must stop reconciliation before any writes.
    class Error < StandardError
    end

    FIELDS = %i[team_slug team_name conference_slug conference_name conference_abbreviation].freeze

    def initialize(year:)
      @year = Integer(year)
      raise ArgumentError, 'YEAR must be a positive integer' unless @year.positive?
    end

    def source_url
      "#{BASE_URL}/cbb/seasons/men/#{year}-standings.html"
    end

    def call
      sleep(SLEEP_COUNT)
      parse(fetch_html)
    end

    def fetch_html
      response = HTTParty.get(source_url, timeout: 30)
      raise Error, "Standings request failed: #{source_url} (HTTP #{response&.code})" unless response&.code == 200

      response.body
    rescue HTTParty::Error, Timeout::Error, SocketError, SystemCallError => error
      raise Error, "Standings request failed: #{source_url}: #{error.message}"
    end

    def parse(html)
      parser = self.class
      memberships = parser.conference_tables(html).flat_map { |table| parse_table(table) }
      parser.validate!(memberships)
      memberships
    end

    def self.validate!(memberships)
      unless memberships.is_a?(Array) && memberships.any? && memberships.all? { |row| valid_row?(row) }
        raise Error, 'Invalid or empty source memberships'
      end

      validate_identities!(memberships)
    end

    def self.validate_identities!(memberships)
      slugs = memberships.pluck(:team_slug)
      raise Error, 'Duplicate source team membership' unless slugs.uniq.size == slugs.size

      memberships.group_by { |row| row.fetch(:conference_slug) }.each_value do |rows|
        raise Error, 'Conflicting source conference identities' unless rows.pluck(:conference_name, :conference_abbreviation).uniq.one?
      end
    end

    def self.valid_row?(row)
      row.is_a?(Hash) && row.values_at(*FIELDS).all? { |value| value.is_a?(String) && value.present? }
    end

    def self.conference_tables(html)
      tables = expanded_document(html).css('table[id^="standings_"]')
      raise Error, 'Unsupported standings structure: no conference tables' if tables.empty?
      raise Error, 'Duplicate source conference tables' unless tables.pluck('id').uniq.size == tables.size

      tables
    end

    def self.expanded_document(html)
      document = Nokogiri::HTML(html)
      document.xpath('//comment()').each do |comment|
        content = comment.text
        comment.replace(Nokogiri::HTML.fragment(content)) if content.include?('<table')
      end
      document
    end

    private

    attr_reader :year

    def parse_table(table)
      rows = table.css('tbody tr').reject { |row| row['class'].to_s.split.include?('thead') }
      raise Error, "Empty source conference: #{table['id']}" if rows.empty?

      rows.map { |row| parse_row(row, table) }
    end

    def parse_row(row, table)
      conference_slug = table['id'].delete_prefix('standings_')
      conference_link = row.at_css('[data-stat="conf_abbr"] a')
      unless conference_link&.[]('href') == "/cbb/conferences/#{conference_slug}/men/#{year}.html"
        raise Error, "Invalid conference link in #{conference_slug}"
      end

      team_identity(row).merge(
        conference_slug:,
        conference_name: table.at_css('caption')&.text.to_s.strip.delete_suffix(' Table'),
        conference_abbreviation: conference_link.text.strip
      )
    end

    def team_identity(row)
      link = row.at_css('[data-stat="school_name"] a')
      path = link&.[]('href').to_s
      { team_slug: path.match(%r{\A/cbb/schools/([^/]+)/men/#{year}\.html\z})&.[](1), team_name: link&.text.to_s.strip }
    end
  end
end
