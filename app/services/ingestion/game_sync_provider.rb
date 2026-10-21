# frozen_string_literal: true

module Ingestion
  # One acquisition and request ceiling for an entire operation, including date retries.
  class GameSyncProvider
    # Explicit operator resumption is required; ActiveJob must not renew this budget.
    class Incomplete < StandardError
      attr_reader :report

      def initialize(report)
        @report = report
        super('Provider game sync incomplete; inspect report and explicitly resume unfinished dates.')
      end
    end

    HELD = %w[invalid ambiguous conflict unmatched incomplete stale superseded protected].freeze
    attr_reader :dates

    def initialize(season:, dates:, provider: nil, options: {})
      @season = season
      @dates = dates.map { |date| HistoricalSyncWindow.parse_date(date) }.uniq.sort
      @policy = GameSyncPolicy.new(provider, options)
      validate_dates
    end

    delegate :scope, to: :@policy

    def cbbd?
      scope[:provider] == 'cbbd'
    end

    def call(date)
      raise ArgumentError, 'Date outside prepared sync run' unless dates.include?(date)
      return GameSyncResult.new(GamesIngestionService.new(date:, season: @season).call).call unless cbbd?
      raise Incomplete, summary.merge(failed_dates: dates) unless acquisition['complete']

      import_date(date)
    end

    def summary
      return { scope:, attempts: 0 } unless cbbd? && dates.any?

      result = acquisition
      complete = result['complete']
      { scope:, retrieval_complete: result.dig('acquisition', 'complete'), acquisition_complete: complete,
        attempts: result.dig('acquisition', 'attempts'), acquisition: result['acquisition'], manifest: result['manifest'],
        deferred_dates: complete ? [] : dates, ignored_observations: ignored_observations }
    end

    def self.held?(game)
      HELD.include?(game[:outcome]) || game[:final_box] == 'missing'
    end

    private

    def ignored_observations
      requested = dates.map(&:iso8601)
      acquisition.fetch('observations').count { |row| requested.exclude?(row['schedule_date']) }
    end

    def validate_dates
      bounds = @season.start_date..@season.end_date
      raise ArgumentError, 'Sync dates outside target season' unless dates.all? { |date| bounds.cover?(date) }
    end

    def import_date(date)
      games = date_rows(date).map { |row| Cbbd::ImportObservation.new(row, @season).call }
      GameSyncResult.new(imported_rows: games.count { |game| game[:applied] }, games:).call
    end

    def date_rows(date)
      acquisition.fetch('observations').select { |row| row['schedule_date'] == date.iso8601 }
    end

    def acquisition
      @acquisition ||= acquire
    rescue StandardError => error
      @acquisition = { 'complete' => false, 'observations' => [],
                       'acquisition' => { 'complete' => false, 'error_class' => error.class.name } }
    end

    def acquire
      return { 'complete' => true, 'observations' => [], 'acquisition' => { 'complete' => true, 'attempts' => 0 } } if dates.empty?

      result = Cbbd::Adapter.new(season: @season.year, start_date: dates.min, end_date: dates.max, **@policy.options).call
      validate_observations(result)
      result
    end

    def validate_observations(result)
      valid = result.fetch('observations').all? do |row|
        row.values_at('provider', 'format', 'semantic_profile', 'normalization_version', 'season') ==
          ['cbbd', scope[:contract_version], scope[:semantic_profile], CanonicalObservation::NORMALIZATION_VERSION, @season.year] &&
          (dates.min..dates.max).cover?(HistoricalSyncWindow.parse_date(row['schedule_date']))
      end
      result['complete'] = result['complete'] == true && result.dig('acquisition', 'complete') == true && valid
    rescue ArgumentError
      result.store('complete', false)
    end
  end
end
