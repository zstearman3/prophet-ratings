# frozen_string_literal: true

require 'date'
require 'json'

module RatingsBackfill
  # Keeps the backend's pinned model and coverage metadata across bounded windows.
  class ChunkPlan
    PREFIX = 'BACKFILL_PLAN '

    attr_reader :data

    def initialize(lines)
      raise ArgumentError, 'Expected exactly one BACKFILL_PLAN JSON line from the planning container' unless lines.one?

      @data = JSON.parse(lines.first.delete_prefix(PREFIX))
      raise ArgumentError, 'BACKFILL_PLAN must contain a JSON object' unless @data.is_a?(Hash)

      %w[season_id model_id model year from through next_date cohort_key initialize_preseason completed_days total_days].each do |key|
        @data.fetch(key)
      end
    end

    def summary
      "model=#{data.fetch('model')} (id=#{data.fetch('model_id')}) " \
        "coverage=#{data.fetch('completed_days')}/#{data.fetch('total_days')} days"
    end

    def complete?
      !data.fetch('next_date')
    end

    def each_request(chunk_days)
      return if complete?

      date_range.step(chunk_days).each do |current|
        yield data.merge('phase' => 'run', 'from' => current.iso8601, 'through' => chunk_end(current, chunk_days),
                         'initialize_preseason' => data.fetch('initialize_preseason') && current == date_range.begin)
      end
    end

    private

    def date_range
      current = Date.iso8601(data.fetch('next_date'))
      first = Date.iso8601(data.fetch('from'))
      last = Date.iso8601(data.fetch('through'))
      raise ArgumentError, 'BACKFILL_PLAN next_date is outside the requested range' unless (first..last).cover?(current)

      current..last
    end

    def chunk_end(current, chunk_days)
      [current + chunk_days - 1, date_range.end].min.iso8601
    end
  end
end
