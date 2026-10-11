# frozen_string_literal: true

require 'bigdecimal'
require 'time'

module Recruiting
  # Versioned saved transcription contract for 247 men's Recruit Composite only.
  class Extract
    SOURCE = '247sports'
    CATEGORY = 'recruit_composite'
    VERSION = '247-recruit-json-v1'
    TEXT_FIELDS = %w[source_url extraction_version observed_at retrieved_at captured_at snapshot_kind snapshot_location
                     coverage_note].freeze
    NUMERIC_FIELDS = %w[rank class_points average_rating commit_count].freeze

    attr_reader :document

    def initialize(bytes)
      text = bytes.dup.force_encoding(Encoding::UTF_8)
      raise ArgumentError, 'Extract must be valid UTF-8' unless text.valid_encoding?

      @document = JSON.parse(text, decimal_class: BigDecimal)
      validate
    end

    def rows
      document.fetch('rows').each_with_index.map { |row, index| Row.new(row, index + 1).to_h }
    end

    def metadata
      document.except('rows')
    end

    def self.timestamp(value)
      unless value.is_a?(String) && value.match?(/(?:Z|[+-]\d{2}:\d{2})\z/)
        raise ArgumentError,
              'Use ISO8601 timestamps with explicit timezone'
      end

      Time.iso8601(value)
    end

    def self.valid_year?(year)
      year.is_a?(Integer) && year.between?(1900, 2200)
    end

    def self.text?(value)
      value.is_a?(String) && value.present?
    end

    private

    def validate
      raise ArgumentError, 'Expected an extract object with rows array' unless document.is_a?(Hash) && document['rows'].is_a?(Array)

      validate_status
      raise ArgumentError, 'Only 247sports recruit_composite all conferences is supported' unless approved_source?
      raise ArgumentError, 'Source year Y must target season Y+1' unless valid_years?

      validate_provenance
    end

    def validate_status
      status = document['source_status']
      raise ArgumentError, "Source failure: #{status}" unless status == 'ok'
    end

    def approved_source?
      document.values_at('provider', 'category', 'conference_scope') == [SOURCE, CATEGORY, 'all']
    end

    def valid_years?
      year = document['source_year']
      self.class.valid_year?(year) && document['target_season'] == year + 1
    end

    def validate_provenance
      raise ArgumentError, 'Missing provenance text fields' unless TEXT_FIELDS.all? { |key| self.class.text?(document[key]) }
      raise ArgumentError, 'Unsupported extraction version' unless document['extraction_version'] == VERSION

      validate_source_snapshot
      validate_dates
    end

    def validate_source_snapshot
      kinds = %w[raw_html factual_transcription]
      raise ArgumentError, 'Snapshot kind must be raw_html or factual_transcription' unless kinds.include?(document['snapshot_kind'])

      expected_url = "https://247sports.com/Season/#{document['source_year']}-Basketball/CompositeTeamRankings/"
      raise ArgumentError, 'Source URL must identify the annual Recruit Composite page' unless document['source_url'] == expected_url
    end

    def validate_dates
      validator = self.class
      %w[observed_at retrieved_at captured_at].each { |key| validator.timestamp(document[key]) }
      validate_as_of
    end

    def validate_as_of
      validator = self.class
      case document.fetch('source_as_of')
      when NilClass
        raise ArgumentError, 'Missing source_as_of requires a nonempty reason' unless validator.text?(document['source_as_of_reason'])
      else
        validator.timestamp(document['source_as_of'])
      end
    end
  end
end
