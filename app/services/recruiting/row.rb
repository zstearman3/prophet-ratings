# frozen_string_literal: true

module Recruiting
  # Auditable normalization; invalid supplied data remains an exclusion, never missing evidence.
  class Row
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
