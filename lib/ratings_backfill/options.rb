# frozen_string_literal: true

require 'date'
require 'optparse'

module RatingsBackfill
  # Parses host-only options without loading Rails or contacting Docker.
  class Options
    DEFINITIONS = {
      year: ['--year YEAR', Integer, 'Season ending year (required)'],
      model: ['--model NAME', 'Stored model name (required)'],
      from: ['--from DATE', 'First date (YYYY-MM-DD)'],
      through: ['--through DATE', 'Last date (YYYY-MM-DD)'],
      initialize_preseason: ['--initialize-preseason', 'Initialize preseason in the first chunk'],
      chunk_days: ['--chunk-days DAYS', Integer, 'Days per fresh container (default: 7)'],
      progress_seconds: ['--progress-seconds SECONDS', Float, 'Elapsed/memory report interval (default: 30)'],
      project: ['--project NAME', 'Existing development Compose project'],
      memory: ['--memory LIMIT', 'Optional web memory cap, for example 1g'],
      help: ['-h', '--help', 'Show this help']
    }.freeze

    attr_reader :values

    def initialize(arguments)
      @values = { chunk_days: 7, progress_seconds: 30, initialize_preseason: false,
                  project: ENV.fetch('COMPOSE_PROJECT_NAME', 'prophet-ratings') }
      @parser = OptionParser.new('Usage: bin/backfill-ratings --year YEAR --model NAME [options]')
      configure_parser
      parse(arguments)
      validate unless values[:help]
    end

    def help
      @parser.to_s
    end

    def request
      values.slice(:year, :model, :from, :through, :initialize_preseason).merge(phase: 'plan')
    end

    def self.iso_date(value)
      raise OptionParser::InvalidArgument, "expected YYYY-MM-DD: #{value}" unless value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      Date.iso8601(value).iso8601
    rescue Date::Error
      raise OptionParser::InvalidArgument, "invalid date: #{value}"
    end

    private

    def configure_parser
      DEFINITIONS.each { |key, definition| add_option(key, definition) }
    end

    def add_option(key, definition)
      @parser.on(*definition) { |value| @values[key] = value }
    end

    def parse(arguments)
      @parser.parse!(arguments)
      raise OptionParser::InvalidArgument, arguments.join(' ') unless arguments.empty?
    end

    def validate
      validate_identity
      validate_limits
      values.slice(:from, :through).each { |key, value| @values[key] = self.class.iso_date(value) }
      validate_range
    end

    def validate_range
      first, last = values.values_at(:from, :through)
      raise OptionParser::InvalidArgument, '--from must not be after --through' if first && last && first > last
    end

    def validate_identity
      year, model = values.values_at(:year, :model)
      raise OptionParser::MissingArgument, '--year and --model are required' unless year && model
      raise OptionParser::InvalidArgument, '--year must be positive' unless year.positive?
      raise OptionParser::InvalidArgument, '--model must not be empty' if model.strip.empty?
    end

    def validate_limits
      raise OptionParser::InvalidArgument, '--chunk-days must be positive' unless values.fetch(:chunk_days).positive?
      raise OptionParser::InvalidArgument, '--progress-seconds must be positive and finite' unless valid_interval?
      raise OptionParser::InvalidArgument, '--project must be a Compose project name' unless valid_project?
      raise OptionParser::InvalidArgument, '--memory must be a positive byte count or unit, for example 1g' unless valid_memory?
    end

    def valid_interval?
      values.fetch(:progress_seconds).between?(Float::MIN, Float::MAX)
    end

    def valid_project?
      values.fetch(:project).match?(/\A[a-z0-9][a-z0-9_-]*\z/)
    end

    def valid_memory?
      !values.key?(:memory) || values.fetch(:memory).match?(/\A[1-9]\d*(?:[bkmgBKMG])?\z/)
    end
  end
end
