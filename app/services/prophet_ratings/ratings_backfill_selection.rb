# frozen_string_literal: true

module ProphetRatings
  # Persisted team/model selection and prerequisites for safe daily checkpoints.
  class RatingsBackfillSelection < Data.define(:season, :version, :dates, :participant_ids)
    PRIOR_KEYS = PreseasonPriorFormula::STATS.map { |stat| "preseason_#{stat}" }.sort.freeze

    def coverage(date_range)
      snapshots = season.team_rating_snapshots.where(ratings_config_version: version, snapshot_date: date_range)
      validate_checkpoints(snapshots)
      snapshots.where(team_season_id: participant_ids).group(:snapshot_date).distinct.count(:team_season_id)
    end

    def initialization_required?(request)
      return false if captured_priors_complete?

      validate_initialization(request)
      true
    end

    def self.validate_prior(prior, config)
      outputs = prior.outputs
      return true if outputs.is_a?(Hash) && outputs.keys.sort == PRIOR_KEYS &&
                     outputs.values.all? { |value| HistoricalRatingsState.valid_value?(value) } &&
                     PreseasonPriorFormula.new(prior.inputs, config).call == outputs

      raise ArgumentError, 'Historical replay requires complete matching captured priors'
    end

    private

    def validate_checkpoints(snapshots)
      key = SeasonParticipationReview.new(season).publication_key
      return unless snapshots.exists?(["stats ->> 'participation_key' IS DISTINCT FROM ?", key])

      raise ArgumentError,
            'Saved checkpoint participation differs from the selected roster; preserve outputs and review a new model version'
    end

    def captured_priors_complete?
      priors = PreseasonPrior.where(ratings_config_version: version, team_season_id: participant_ids).to_a
      return false if priors.empty?
      if priors.size != participant_ids.size
        raise ArgumentError, 'Included teams have incomplete captured prior coverage; review the selected model'
      end

      priors.all? { |prior| self.class.validate_prior(prior, version.config) }
    end

    def validate_initialization(request)
      if season.team_rating_snapshots.exists?(ratings_config_version: version) ||
         season.predictions.exists?(ratings_config_version: version)
        raise ArgumentError, 'Cannot initialize over existing model outputs; review captured prior coverage'
      end
      raise ArgumentError, 'New model inputs require --initialize-preseason' unless request['initialize_preseason'] == true
      raise ArgumentError, 'Preseason initialization requires starting at season opening' unless dates.begin == season.start_date
    end
  end
end
