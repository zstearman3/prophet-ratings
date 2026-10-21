# frozen_string_literal: true

module Ingestion
  # Provider-neutral raw inputs. Missing values remain missing; only persisted whitelist fields reach formulas.
  class GameObservation
    # Invalid contract data is retained for review without domain writes.
    class Invalid < StandardError; end

    VERSION = 'ingestion-v1'
    PROFILES = %w[official-team-totals-v1 sports-reference-legacy-v1].freeze
    STAT_KEYS = (%i[minutes] + ProphetRatings::GameBoxScoreValidator::REQUIRED_COUNTS).freeze
    SIDES = %i[home away].freeze
    STATUSES = %w[scheduled live final postponed cancelled unknown].freeze
    attr_reader :data

    def initialize(payload)
      @data = payload.deep_symbolize_keys.deep_dup
    end

    def validate
      normalize
      self
    rescue ArgumentError, KeyError, NoMethodError => error
      raise Invalid, error.message
    end

    def final?
      data[:source_status] == 'final' && data[:source_completed] == true && data[:completion_evidence].present?
    end

    def schedule_projection?
      data[:external_game_id].blank? && data[:source_status] == 'scheduled' && data[:source_completed] == false
    end

    def complete?
      SIDES.all? { |label| self.class.complete_side?(data.fetch(label)) }
    end

    def strict_final?
      final? && complete?
    end

    def validate_duration
      duration = self.class.count(data[:duration_minutes])
      raise Invalid, 'duration must be 40 plus five minutes per overtime' unless duration && duration >= 40 && ((duration - 40) % 5).zero?

      validate_side_minutes
      raise Invalid, 'final scores must differ' if data[:home][:score] == data[:away][:score]
    end

    def self.complete_side?(side)
      side[:score].present? && STAT_KEYS.all? { |field| side.fetch(:stats).fetch(field).present? }
    end

    def self.normalize_side(side, profile)
      validate_side_metadata(side, profile)
      stats = side[:stats].to_h
      side.merge(score: count(side[:score]), stats: normalize_stats(stats), field_availability: availability(stats))
    end

    def self.validate_side_metadata(side, profile)
      name, external_id, side_profile = side.values_at(:name, :external_team_id, :semantic_profile)
      validate_string(name, 'participant name')
      validate_optional_string(external_id, :external_team_id)
      raise Invalid, 'mixed semantic profiles' unless [nil, profile].include?(side_profile)
    end

    def self.normalize_stats(stats)
      raise Invalid, 'unsupported statistics' if (stats.keys - STAT_KEYS).any?

      STAT_KEYS.index_with { |key| count(stats[key]) }
    end

    def self.availability(stats)
      STAT_KEYS.index_with { |field| availability_reason(stats[field]) }
    end

    def self.availability_reason(value)
      case value
      when NilClass then 'missing'
      when String then value.strip.empty? ? 'blank' : 'observed'
      else 'observed'
      end
    end

    def self.validate_optional_string(value, label)
      value&.then { |present| validate_string(present, label) }
    end

    def self.validate_string(value, label)
      raise Invalid, "#{label} must be a nonblank opaque string" unless value.is_a?(String) && value.strip.present?
    end

    def self.count(value)
      case value
      when NilClass then nil
      when String then string_count(value)
      when Integer then integer_count(value)
      else raise Invalid, 'counts must be nonnegative integers'
      end
    end

    def self.string_count(value)
      return nil if value.strip.empty?
      raise Invalid, 'counts must be nonnegative integers' unless value.match?(/\A\d+\z/)

      integer_count(value.to_i)
    end

    def self.integer_count(value)
      raise Invalid, 'counts must fit database integers' unless value.between?(0, 2_147_483_647)

      value
    end

    def self.timestamp(value)
      value&.then { |present| parse_timestamp(present.to_s) }
    end

    def self.parse_timestamp(text)
      raise Invalid, 'timestamp requires RFC3339 with offset' unless text.match?(/T.*(?:Z|[+-]\d\d:\d\d)\z/)

      Time.iso8601(text).iso8601(6)
    end

    private

    def normalize
      validate_metadata
      validate_time
      normalize_sides
    end

    def normalize_sides
      SIDES.each { |label| data[label] = self.class.normalize_side(data.fetch(label), data[:semantic_profile]) }
    end

    def validate_metadata
      raise Invalid, 'unsupported contract version' unless data[:contract_version] == VERSION
      raise Invalid, 'unsupported semantic profile' unless PROFILES.include?(data[:semantic_profile])
      raise Invalid, 'unknown source status' unless STATUSES.include?(data[:source_status])

      validate_identifiers
      validate_completion
    end

    def validate_identifiers
      validator = self.class
      %i[provider adapter_revision].each { |key| validator.validate_string(data[key], key) }
      validator.validate_optional_string(data[:external_game_id], :external_game_id)
    end

    def validate_completion
      completed = data[:source_completed]
      raise Invalid, 'source_completed must be boolean' unless [true, false].include?(completed)
      raise Invalid, 'source completion requires final status and evidence' if completed && !final?
    end

    def validate_time
      data[:schedule_date] = Date.iso8601(data.fetch(:schedule_date).to_s).iso8601
      %i[captured_at source_updated_at start_time].each { |key| data[key] = self.class.timestamp(data[key]) }
      raise Invalid, 'captured_at required' unless data[:captured_at]

      validate_start_time
    end

    def validate_start_time
      start = data[:start_time]
      return unless start
      return if Game.schedule_date_for(Time.iso8601(start)).iso8601 == data[:schedule_date]

      raise Invalid, 'start_time conflicts with Eastern schedule date'
    end

    def validate_side_minutes
      minutes = self.class.count(data[:duration_minutes]) * 5
      return if SIDES.all? { |label| data[label][:stats][:minutes] == minutes }

      raise Invalid, 'side minutes inconsistent with duration'
    end
  end
end
