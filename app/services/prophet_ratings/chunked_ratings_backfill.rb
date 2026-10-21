# frozen_string_literal: true

require 'digest'
require 'benchmark'

module ProphetRatings
  # Daily commits within a bounded process; saved snapshot coverage is the resume checkpoint.
  class ChunkedRatingsBackfill
    def initialize(request, output: $stdout)
      raise ArgumentError, 'Backfill request must be an object' unless request.is_a?(Hash)

      @request = request.stringify_keys
      @output = output
      @selection = nil
      @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def plan
      Season.with_ratings_lock do
        load_selection
        plan_data
      end
    end

    def run
      Season.with_ratings_lock do
        prepare_execution
        run_dates
      end
    end

    def self.date_range(season, request)
      allowed = season.start_date..[season.end_date, Game.current_schedule_date].min
      first = strict_date(request.fetch('from', allowed.begin.iso8601))
      last = strict_date(request.fetch('through', allowed.end.iso8601))
      unless first <= last && allowed.cover?(first) && allowed.cover?(last)
        raise ArgumentError, 'Choose an ordered date range within the season and no later than Eastern today'
      end

      first..last
    end

    def self.strict_date(value)
      date = Date.iso8601(value)
      raise ArgumentError, 'Dates must be exact YYYY-MM-DD strings' unless date.iso8601 == value

      date
    end

    private

    def load_selection
      @selection = self.class.load(@request)
    end

    public_class_method def self.load(request)
      season = selected_season(request)
      SeasonParticipationReview.new(season).validate
      version = selected_version(request)
      version.settings
      RatingsBackfillSelection.new(season, version, date_range(season, request), season.rating_team_seasons.order(:id).ids)
    end

    public_class_method def self.selected_season(request)
      request.key?('season_id') ? Season.find(request.fetch('season_id')) : Season.find_by!(year: request.fetch('year'))
    end

    public_class_method def self.selected_version(request)
      if request.key?('model_id')
        RatingsConfigVersion.find(request.fetch('model_id'))
      else
        RatingsConfigVersion.find_by!(name: request.fetch('model'))
      end
    end

    delegate :season, :version, :dates, :participant_ids, to: :@selection, private: true

    def selection_context
      raise ArgumentError, 'Backfill requires prepared included team seasons' if participant_ids.empty?

      self.class.context(season, version, participant_ids)
    end

    public_class_method def self.context(season, version, ids)
      context = { 'season_id' => season.id, 'model_id' => version.id, 'model' => version.name, 'year' => season.year,
                  'season_start' => season.start_date.iso8601, 'season_end' => season.end_date.iso8601 }
      context.merge('cohort_key' => Digest::SHA256.hexdigest([context, ids].to_json))
    end

    def plan_data
      initialize_preseason = initialization_required?
      counts = coverage(dates)
      next_date = dates.find { |date| counts.fetch(date, 0) != participant_ids.size }
      selection_context.merge(self.class.range_metadata(dates, next_date)).merge('initialize_preseason' => initialize_preseason)
    end

    public_class_method def self.range_metadata(range, next_date)
      first = range.begin
      last = range.end
      bounds = { 'from' => first.iso8601, 'through' => last.iso8601 }
      bounds.merge('range_start' => bounds.fetch('from'), 'range_end' => bounds.fetch('through'),
                   'next_date' => next_date&.iso8601, 'completed_days' => ((next_date || (last + 1)) - first).to_i,
                   'total_days' => (last - first).to_i + 1)
    end

    delegate :coverage, to: :@selection, private: true

    def initialization_required?
      @selection.initialization_required?(@request)
    end

    def run_dates
      pending_dates = dates.to_a
      initialize_day(pending_dates.shift) if initialization_required?
      pending_dates.each { |date| run_day(date) }
    end

    def prepare_execution
      load_selection
      context = selection_context
      raise ArgumentError, 'Backfill selection changed; rerun planning' unless @request.slice(*context.keys) == context

      validate_resume_prefix
    end

    def validate_resume_prefix
      bounds = self.class.date_range(season, 'from' => @request.fetch('range_start'), 'through' => @request.fetch('range_end'))
      raise ArgumentError, 'Chunk date range lies outside the planned window' unless bounds.cover?(dates.begin) && bounds.cover?(dates.end)
      raise ArgumentError, 'Earlier dates are incomplete; rerun planning to find the first missing checkpoint' if missing_prefix?(bounds)
    end

    def missing_prefix?(bounds)
      prefix = bounds.begin...dates.begin
      counts = coverage(prefix)
      prefix.any? { |date| counts.fetch(date, 0) != participant_ids.size }
    end

    def run_day(date)
      timed_day(date) do
        ResumeSeasonRatingsJob.new.perform(season.id, start_date: date, end_date: date, ratings_config_version_id: version.id)
      end
    end

    def initialize_day(date)
      timed_day(date) do
        GenerateSeasonRatingsJob.new.perform(season.id, rebuild: true, date_range: date..date, run_preseason: true,
                                                        ratings_config_version_id: version.id)
      end
    end

    def timed_day(date)
      elapsed = Benchmark.realtime do
        report(date, 'starting')
        yield
      end
      report(date, 'committed', elapsed)
    end

    def report(date, status, day_elapsed = 0)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started
      @output.puts("[backfill] date=#{date.iso8601} status=#{status} elapsed=#{elapsed.round(1)}s day_elapsed=#{day_elapsed.round(1)}s")
      @output.flush
    end
  end
end
