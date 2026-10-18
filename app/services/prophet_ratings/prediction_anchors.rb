# frozen_string_literal: true

module ProphetRatings
  # Versioned centers travel with ratings: mixed prior/observed teams need different centers.
  class PredictionAnchors
    FIELDS = %w[adj_offensive_efficiency adj_defensive_efficiency adj_pace].freeze

    def self.prior_weight(season, as_of, config)
      days = [(as_of.to_date - season.start_date).to_i, 0].max
      [1.0 - (days.to_f / config.dig(:weighting, :preseason_decay_days)), config.dig(:weighting, :min_preseason_weight)].max.round(4)
    end

    def self.reset(season, version, as_of)
      model_id = version.id
      teams = validated_teams(season, model_id)
      anchors = prior_centers(teams).merge('model_version_id' => model_id, 'as_of' => as_of.to_date.iso8601)
      teams.each { |team| team.update!(prior_state(team).merge(rating_anchors: anchors)) }
    end

    def self.prior_state(team)
      stats = OverallRatingsCalculator::ADJUSTED_STATS.values.flatten.map(&:to_s) & team.attribute_names
      stats.index_with(nil).merge(PreseasonInitializer.prior_ratings(team))
    end

    def self.validated_teams(season, model_id)
      season.rating_team_seasons.order(:team_id).to_a.each do |team|
        raise ArgumentError, 'Coherent ratings require captured preseason priors' unless captured_prior?(team, model_id)
      end
    end

    def self.captured_prior?(team, model_id)
      team.matching_prior?(model_id) && team.preseason_prior.outputs.values.all? { |value| HistoricalRatingsState.valid_value?(value) }
    end

    def self.prior_centers(teams)
      efficiency = prior_mean(teams, :preseason_adj_offensive_efficiency)
      pace = prior_mean(teams, :preseason_adj_pace)
      # Preseason publication historically centers both efficiencies on mean prior offense.
      { 'adj_offensive_efficiency' => efficiency, 'adj_defensive_efficiency' => efficiency, 'adj_pace' => pace }
    end

    def self.prior_mean(teams, field)
      teams.sum { |team| team.public_send(field).to_f } / teams.size.to_f
    end

    def self.validate_live(team, version, as_of)
      anchors = team.rating_anchors
      return if anchors['model_version_id'] == version.id && anchors['as_of'] == as_of.to_date.iso8601 &&
                anchors.values_at(*FIELDS).all? { |value| finite?(value) }

      raise ArgumentError, 'Live rating anchors must match the selected model and publication date; recalculate ratings'
    end

    def self.finite?(value)
      value.is_a?(Numeric) && value.finite?
    end

    def self.publication_stats(team, stats, context)
      return stats unless EarlySeasonPolicy.enabled?(context.fetch(:config))

      supported = EarlySeasonPolicy.supported_stats(stats, context)
      return supported if supported.empty?

      blend_anchors(team, supported, context)
    end

    def self.blend_anchors(team, stats, context)
      weight, center = context.values_at(:weight, :center)
      anchors = team.rating_anchors
      centers = anchors.slice(*stats.keys.map(&:to_s)).transform_values { |value| (weight * value) + ((1 - weight) * center) }
      stats.merge(rating_anchors: anchors.merge(centers))
    end

    def self.expected(snapshots, fields, options)
      values = snapshots.zip(fields).sum { |snapshot, field| snapshot.public_send(field) }
      values - prediction_center(snapshots, fields, options)
    end

    def self.snapshot_center(snapshot, field)
      anchors = snapshot.stats.fetch('rating_anchors', {})
      value = anchors[field]
      unless finite?(value) && anchors['model_version_id'] == snapshot.ratings_config_version_id &&
             anchors['as_of'] == snapshot.snapshot_date&.iso8601
        raise ArgumentError, 'Prediction requires stored rating anchors matching snapshot model/date'
      end

      value
    end

    def self.prediction_center(snapshots, fields, options)
      return options.fetch(:fallback) unless EarlySeasonPolicy.enabled?(options.fetch(:config))

      centers = snapshots.zip(fields).map { |snapshot, field| snapshot_center(snapshot, field) }
      centers.sum / 2.0
    end
  end
end
