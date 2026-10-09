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
      reports = @years.map { |year| season_report(Season.find_by!(year:)) }
      {
        benchmark: 'fixed preseason; no profiles, no in-season transition or confidence labels',
        source_config: @source_version.name, candidate_config: config,
        split: self.class.split_description(reports),
        seasons: reports,
        decision: 'Retain production defaults. This bounded benchmark does not establish improvement or tune coefficients.'
      }
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
