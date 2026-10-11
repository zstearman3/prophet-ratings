# frozen_string_literal: true

module Scraper
  # Discovers the current annual public request without cached IDs or nonces.
  class CoachingChangesScraper
    # A failed or unsupported source must never be treated as an empty import.
    class Error < StandardError; end

    FIELDS = %w[school conference old_coach new_coach].freeze

    def initialize(year:)
      @year = Integer(year.to_s, 10)
      raise ArgumentError, 'YEAR must be an integer from 2 to 9999' unless (2..9999).cover?(@year)
    end

    def source_url
      "https://hoopdirt.com/#{year - 1}-coaching-changes-tracker/"
    end

    def call
      request_url = table_configuration(fetch(source_url)).fetch('init_config').fetch('data_request_url')
      self.class.validate_request!(request_url)
      parse_rows(fetch(request_url))
    rescue JSON::ParserError, KeyError, TypeError => error
      raise Error, "Malformed coaching tracker: #{error.class}"
    end

    def self.validate!(rows)
      raise Error, 'Malformed or empty D1 coaching table; no candidates changed' unless rows.is_a?(Array) && rows.any? &&
                                                                                        rows.all? { |row| valid_row?(row) }

      schools = rows.map { |row| row.fetch('value').fetch('school').strip.downcase }
      raise Error, 'Duplicate schools in D1 coaching table' unless schools.uniq.size == schools.size
    end

    def self.valid_row?(row)
      return false unless row.is_a?(Hash)

      values = row['value']
      values.is_a?(Hash) && FIELDS.all? { |key| values[key].is_a?(String) } && values['school'].strip.present?
    end

    def self.validate_request!(url)
      raise Error, 'Unsupported coaching table request location' unless valid_location?(url)

      query = URI.decode_www_form(URI.parse(url).query.to_s).to_h
      return if query['target_action'] == 'get-all-data' && query['table_id'].to_s.match?(/\A\d+\z/) && unlimited?(query)

      raise Error, 'Unsupported partial coaching table request'
    rescue URI::InvalidURIError, ArgumentError
      raise Error, 'Malformed coaching table request location'
    end

    def self.valid_location?(url)
      uri = URI.parse(url)
      uri.scheme == 'https' && uri.host == 'hoopdirt.com' && uri.path == '/wp-admin/admin-ajax.php' && !uri.userinfo
    end

    def self.unlimited?(settings)
      settings.is_a?(Hash) && %w[skip_rows limit_rows].all? { |key| settings[key].to_s == '0' }
    end

    def self.script_config(script)
      match = script.text.match(/window\[['"]ninja_table_instance_\d+['"]\]\s*=\s*(\{.*\})\s*;?\s*\z/m)
      JSON.parse(match[1]) if match
    end

    private

    attr_reader :year

    def fetch(url)
      response = HTTParty.get(url, timeout: 30, follow_redirects: false)
      raise Error, "Coaching source HTTP #{response&.code}; refresh the tracker and retry" unless response&.code == 200

      response.body
    rescue HTTParty::Error, Timeout::Error, SocketError, SystemCallError => error
      raise Error, "Coaching source request failed: #{error.class}; refresh the tracker and retry"
    end

    def parse_rows(body)
      rows = JSON.parse(body)
      self.class.validate!(rows)
      rows.map { |row| row.fetch('value').slice(*FIELDS).symbolize_keys }
    end

    def table_configuration(html)
      configs = script_configurations(html)
      selected = configs.select { |config| config['title'].to_s.match?(/\ADivision I \(D1\) Coaching Changes \(#{year - 1}\)\z/) }
      raise Error, 'Missing or ambiguous annual D1 table configuration' unless selected.one?

      validate_configuration(selected.first)
    end

    def script_configurations(html)
      parser = self.class
      Nokogiri::HTML(html).css('script').filter_map { |script| parser.script_config(script) }
    end

    def validate_configuration(configuration)
      columns = configuration.fetch('columns')
      raise Error, 'Malformed D1 table columns' unless columns.is_a?(Array) && (FIELDS - columns.pluck('key')).empty?
      raise Error, 'Unsupported partial D1 table' unless self.class.unlimited?(configuration.fetch('settings'))

      configuration
    end
  end
end
