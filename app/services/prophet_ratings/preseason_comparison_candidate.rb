# frozen_string_literal: true

module ProphetRatings
  # Preregistered hypotheses, never published model versions or fitted parameters.
  class PreseasonComparisonCandidate
    NAMES = %w[baseline_calendar multiyear_calendar baseline_effective_games].freeze

    def initialize(name, config)
      @name = name
      @config = config.deep_stringify_keys
    end

    def self.source_mean(snapshots, stat)
      StatisticsUtils.average(snapshots.map { |snapshot| snapshot.public_send(stat).to_f })
    end

    def prior(previous, older, baselines)
      older_values = older ? older.attributes : baselines
      PreseasonPriorFormula::STATS.index_with do |stat|
        blend(previous.public_send(stat).to_f, older_values.fetch(stat).to_f, baselines.fetch(stat))
      end
    end

    def blend(last, older, baseline)
      if @name == 'multiyear_calendar'
        ((0.70 * last) + (0.15 * older) + (0.15 * baseline)).round(3)
      else
        weight = @config.fetch('preseason').fetch('previous_season_weight')
        ((weight * last) + ((1 - weight) * baseline)).round(3)
      end
    end

    def weight(days:, games:, effective_games:)
      return 1.0 if games < 2
      return (8.0 / (8.0 + effective_games)).round(4) if @name == 'baseline_effective_games'
      return 1.0 if days <= @config.fetch('preseason').fetch('adjustment_start_after_days')

      weighting = @config.fetch('weighting')
      [1 - ([days, 0].max.to_f / weighting.fetch('preseason_decay_days')), weighting.fetch('min_preseason_weight')].max.round(4)
    end
  end
end
