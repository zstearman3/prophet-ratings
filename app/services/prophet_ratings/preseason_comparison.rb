# frozen_string_literal: true

module ProphetRatings
  # Read-only, fixed preseason benchmark. Never uses current-season ratings or backfills.
  class PreseasonComparison
    CANDIDATE_WEIGHTS = [0.85, 0.70, 0.55].freeze

    def initialize(years:, source_config_name:, ratings_config_version: nil)
      @years = years.map { |year| Integer(year) }.uniq.sort
      raise ArgumentError, 'Choose between one and five season years' unless (1..5).cover?(@years.size)

      @source_version = RatingsConfigVersion.find_by!(name: source_config_name)
      @ratings_config_version = RatingsConfigVersion.resolve(ratings_config_version)
    end

    def call
      config = @ratings_config_version.settings.deep_stringify_keys
      PreseasonComparison.validate_model(config)
      reports = @years.map { |year| season_report(Season.find_by!(year:)) }
      {
        benchmark: 'opening-period game-time performance; fixed and sequential no-profile reconstructions',
        source_config: @source_version.name, candidate_config: config,
        sequential_candidates: {
          baseline_calendar: 'Configured previous weight, day gate, calendar decay and floor',
          multiyear_calendar: '0.70 previous + 0.15 second year + 0.15 cohort baseline; absent second year uses baseline',
          baseline_effective_games: 'Previous prior; two-result qualification; weight 8/(8+sum(recency weights)), no day gate/floor'
        },
        split: self.class.split_description(reports),
        seasons: reports,
        required_data: ['At least two timestamp-eligible seasons: earlier selection, latest held-out evaluation',
                        'Pre-opening previous/two-year snapshots with immutable source timestamps and known venues',
                        'Prepared paired final efficiency/pace records created and last revised before each prediction date'],
        decision: 'Retain production defaults. This bounded benchmark does not establish improvement or tune coefficients.'
      }
    end

    def self.validate_model(config)
      return unless config.dig('preseason', 'coaching')

      raise ArgumentError, 'Preseason comparison supports v1 team-history candidates only; select a model without preseason.coaching. ' \
                           'Coaching evaluation requires archived reviewed inputs and common-game evidence.'
    end

    def self.split_description(reports)
      available = reports.select { |report| report.fetch(:eligible_games).positive? }.pluck(:year)
      if available.size < 2
        return { evaluation: available, tuning: [], limitation: 'Fewer than two eligible seasons; no independent tuning/evaluation split' }
      end

      { tuning: available[0...-1], evaluation: [available.last], limitation: 'Candidates fixed in advance; no automatic selection' }
    end

    private

    def season_report(season)
      PreseasonComparisonSeason.new(season:, source_version: @source_version, ratings_config_version: @ratings_config_version).call
    end
  end
end
