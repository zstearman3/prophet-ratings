# frozen_string_literal: true

module Ingestion
  module Cbbd
    # Strict integer values retain their lexical representation and missingness.
    class StatField
      MAX_INTEGER = 2_147_483_647
      ABSENT = Object.new.freeze

      def initialize(raw, path)
        @path = path
        @raw = path.reduce(raw) { |parent, key| self.class.lookup(parent, key) }
      end

      def call
        { 'value' => value, 'availability' => value ? 'observed' : 'unknown', 'reason' => reason,
          'raw' => @raw.equal?(ABSENT) ? nil : @raw, 'source_path' => @path.join('.'), 'units' => 'count',
          'derivation' => @raw.is_a?(String) && value ? 'trimmed_digit_string' : 'direct' }
      end

      def self.lookup(parent, key)
        parent.is_a?(Hash) ? parent.fetch(key, ABSENT) : ABSENT
      end

      private

      def reason
        return 'absent' if @raw.equal?(ABSENT)
        return 'source_null' if @raw.is_a?(NilClass)
        return 'blank' if @raw.is_a?(String) && @raw.strip.empty?

        'invalid_nonnegative_integer' unless value
      end

      def value
        candidate = parsed
        candidate if candidate&.between?(0, MAX_INTEGER)
      end

      def integer_float
        return unless @raw.finite?

        integer = @raw.to_i
        integer if @raw == integer
      end

      def digit_string
        @raw.strip[/\A\d+\z/]&.to_i
      end

      def parsed
        case @raw
        when Integer then @raw
        when Float then integer_float
        when String then digit_string
        end
      end
    end
  end
end
