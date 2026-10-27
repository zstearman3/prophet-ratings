# frozen_string_literal: true

module Recruiting
  # CBBD men's high-school composite class points, read from retained decimal-aware JSON.
  class CbbdExtract < Extract
    VERSION = 'cbbd-team-recruiting-json-v1'
    PROVIDER = 'cbbd'

    def self.source_url(year)
      "https://api.collegebasketballdata.com/recruiting/teams?year=#{year}"
    end

    def self.normalize(bytes, year)
      rows = JSON.parse(bytes, decimal_class: BigDecimal)
      raise ArgumentError, 'Expected CBBD recruiting rows array' unless rows.is_a?(Array)

      rows.map { |row| normalize_row(row, year) }
    end

    def self.normalize_row(row, year)
      raise ArgumentError, 'Invalid CBBD recruiting row/year/identity' unless valid_identity?(row, year)

      rating, ranking = row.values_at('rating', 'ranking')
      raise ArgumentError, 'Invalid CBBD recruiting rating' unless valid_points?(rating)
      raise ArgumentError, 'Invalid CBBD recruiting rank' unless ranking.is_a?(NilClass) || positive_integer?(ranking)

      { 'provider' => PROVIDER, 'provider_team_id' => row.fetch('teamId').to_s, 'team_label' => row.fetch('team'),
        'team_url' => nil, 'rank' => ranking, 'class_points' => Row.normalized(rating),
        'average_rating' => nil, 'commit_count' => nil, 'source_row' => row.as_json }
    end

    def self.valid_identity?(row, year)
      row.is_a?(Hash) && valid_year?(year) && matching_year?(row['year'], year) && positive_integer?(row['teamId']) && text?(row['team'])
    end

    def self.matching_year?(value, year)
      value.is_a?(Integer) && value == year
    end

    def self.positive_integer?(value)
      value.is_a?(Integer) && value.positive?
    end

    def self.valid_points?(value)
      value.is_a?(NilClass) || (value.is_a?(Numeric) && Row.normalized(value).present?)
    end

    def verify_snapshot(bytes)
      verify_bundle(JSON.parse(bytes))
    rescue IndexError, TypeError => error
      raise ArgumentError, "Invalid CBBD retained response: #{error.message}"
    end

    def verify_bundle(snapshot)
      captures = snapshot.fetch('captures')
      captures.each { |capture| self.class.verify_capture(capture) }
      verify_selected(captures.fetch(snapshot.fetch('selected_capture')))
    end

    def self.verify_capture(capture)
      body = Base64.strict_decode64(capture.fetch('body_base64'))
      raise ArgumentError, 'CBBD retained response hash changed' unless Digest::SHA256.hexdigest(body) == capture.fetch('sha256')
    end

    def verify_selected(selected)
      year = document.fetch('source_year')
      request = { 'endpoint' => '/recruiting/teams', 'year' => year }
      unless selected.dig('metadata', 'request') == request && selected.dig('metadata', 'outcome') == 'success' &&
             selected.dig('metadata', 'status') == 200
        raise ArgumentError, 'CBBD selected response does not match the successful annual request'
      end

      expected = self.class.normalize(Base64.strict_decode64(selected.fetch('body_base64')), year)
      raise ArgumentError, 'CBBD extract differs from retained response' unless expected == document.fetch('rows')
    end

    private

    def approved_source?
      document.values_at('provider', 'category', 'conference_scope') == [PROVIDER, CATEGORY, 'all']
    end

    def validate_provenance
      raise ArgumentError, 'Missing provenance text fields' unless TEXT_FIELDS.all? { |key| Extract.text?(document[key]) }
      raise ArgumentError, 'Unsupported extraction version' unless document['extraction_version'] == VERSION
      unless document['snapshot_kind'] == 'raw_json_bundle' && document['source_url'] == self.class.source_url(document['source_year'])
        raise ArgumentError, 'CBBD source must identify the annual team recruiting request'
      end

      validate_dates
    end
  end
end
