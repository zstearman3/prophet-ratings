# frozen_string_literal: true

module RatingsBackfill
  # Polls memory periodically without querying the application database.
  class Progress
    def initialize(settings)
      @settings = settings
      @started = self.class.now
      @next_report = @started + settings.fetch(:progress_seconds)
    end

    def report_if_due
      current = self.class.now
      return if current < @next_report

      report(current)
      @next_report = current + @settings.fetch(:progress_seconds)
    end

    def report(current)
      name = @settings.fetch(:name)
      memory = @settings.fetch(:docker).memory(name)
      @settings.fetch(:output).write("[backfill] #{@settings.fetch(:label)} elapsed=#{(current - @started).round(1)}s " \
                                     "memory=#{memory} container=#{name}\n")
    end

    def self.now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
