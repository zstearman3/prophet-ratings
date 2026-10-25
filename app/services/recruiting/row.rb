# frozen_string_literal: true

module Recruiting
  # Auditable normalization; invalid supplied data remains an exclusion, never missing evidence.
  class Row
    MISSING_PROVIDER_ID_ERROR = 'provider_team_id: preserve nonempty source identity'
    MISSING_PROVIDER_ID_WARNING = '247Sports did not provide a school identifier. Confirm the team assignment before approving.'

    def initialize(raw, number)
      @raw = raw
      @number = number
    end

    def to_h
      return { 'row_number' => @number, 'raw' => @raw, 'errors' => ['Expected row object'] } unless @raw.is_a?(Hash)

      { 'row_number' => @number, 'raw' => @raw, 'values' => values, 'errors' => errors }
    end

    def values
      Extract::NUMERIC_FIELDS.index_with { |key| self.class.normalized(@raw[key]) }
    end

    def self.normalized(value)
      return if value.is_a?(NilClass)

      number = BigDecimal(value.to_s, exception: false)
      number.to_s('F') if number&.finite? && !number.negative?
    end

    def errors
      identity_errors + Extract::NUMERIC_FIELDS.filter_map { |key| self.class.numeric_error(key, @raw[key]) }
    end

    # Retain original validation evidence; an approved internal mapping can resolve a missing external ID.
    def self.review_errors(row)
      resolved = missing_provider_id?(row['raw']) ? [MISSING_PROVIDER_ID_ERROR] : []
      if excluded_unranked?(row)
        resolved += ['team_label: preserve nonempty source identity', 'team_url: preserve nonempty source identity',
                     'rank: requires positive integer']
      end

      row.fetch('errors') - resolved
    end

    # 247 also lists unlinked schools at rank zero. They may be omitted explicitly, never imported as ranked inputs.
    def self.excluded_unranked?(row)
      raw = row['raw']
      return false unless row['excluded'] == true && missing_provider_id?(raw)

      raw['team_url'].is_a?(NilClass) && normalized(raw['rank']) == '0.0' &&
        [NilClass, String].include?(raw['team_label'].class)
    end

    def self.review_warnings(row)
      return ['Unlinked, unranked source entry excluded; original evidence retained.'] if excluded_unranked?(row)
      return [] if review_errors(row) == row.fetch('errors')

      [MISSING_PROVIDER_ID_WARNING]
    end

    def self.missing_provider_id?(raw)
      return false unless raw.is_a?(Hash)

      identity = raw['provider_team_id']
      case identity
      when NilClass, String then identity.blank?
      else false
      end
    end

    def self.numeric_error(key, value)
      return if value.is_a?(NilClass)

      normalized_value = normalized(value)
      return "#{key}: requires finite nonnegative decimal" unless normalized_value
      return unless %w[rank commit_count].include?(key)

      integer_error(key, BigDecimal(normalized_value))
    end

    def self.integer_error(key, number)
      return if number.frac.zero? && (key != 'rank' || number.positive?)

      "#{key}: requires #{key == 'rank' ? 'positive' : 'nonnegative'} integer"
    end

    def identity_errors
      %w[team_label provider_team_id team_url].filter_map do |key|
        "#{key}: preserve nonempty source identity" unless Extract.text?(@raw[key])
      end
    end
  end
end
