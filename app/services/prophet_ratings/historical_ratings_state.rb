# frozen_string_literal: true

module ProphetRatings
  # Every date is solved from captured priors and bounded results, not a mutable checkpoint.
  class HistoricalRatingsState
    def initialize(season, version)
      @season = season
      @version = version
    end

    def restore
      records = @season.team_seasons
      raise ArgumentError, 'Historical replay requires prepared team seasons and captured priors' unless records.exists?

      records.find_each { |team_season| restore_team(team_season) }
    end

    def reconstruct(games, date)
      cutoff = date - 1
      OverallRatingsCalculator.new(@season, ratings_config_version: @version)
                              .call(as_of: cutoff, replay: true, publish_snapshots: false)
      games.each { |game| reconstruct_game(game, cutoff) }
    end

    def self.snapshot(team_season, date)
      raise ArgumentError, 'Historical game lacks a prepared participant' unless team_season

      team_season.reload
      attributes = team_season.attributes
      TeamRatingSnapshot.new(team: team_season.team, team_season:, season: team_season.season,
                             ratings_config_version: team_season.ratings_config_version,
                             snapshot_date: date, **attributes.slice('rating', *ForecastContext::RATING_FIELDS).symbolize_keys,
                             stats: attributes.slice(*TeamRatingSnapshot::STORED_STATS).merge(
                               'reconstruction' => { 'preseason_prior_id' => team_season.preseason_prior_id,
                                                     'result_cutoff' => date.iso8601 }
                             ))
    end

    private

    def reconstruct_game(game, cutoff)
      snapshots = [game.home_team_season, game.away_team_season].map { |record| self.class.snapshot(record, cutoff) }
      GamePredictionBuilder.new(game, ratings_config_version: @version).reconstruct(snapshots:)
    end

    def restore_team(team_season)
      prior = PreseasonPrior.find_by(team_season:, ratings_config_version: @version)
      outputs = prior&.outputs
      validate_prior(outputs, prior&.inputs)
      team_season.update!(self.class.restored_attributes(team_season.attribute_names, outputs)
                              .merge(preseason_prior: prior, ratings_config_version: @version))
    end

    public_class_method def self.restored_attributes(names, outputs)
      stats = OverallRatingsCalculator::ADJUSTED_STATS.values.flatten.map(&:to_s) & names
      core = outputs.transform_keys { |key| key.delete_prefix('preseason_') }
      stats.index_with(nil).merge(outputs).merge(core)
    end

    public_class_method def self.valid_value?(value)
      value.is_a?(Numeric) && value.finite? && value.positive?
    end

    def validate_prior(outputs, inputs)
      keys = PreseasonPriorFormula::STATS.map { |stat| "preseason_#{stat}" }
      return if outputs && outputs.keys.sort == keys.sort &&
                outputs.values.all? { |value| self.class.valid_value?(value) } &&
                PreseasonPriorFormula.new(inputs, @version.config).call == outputs

      raise ArgumentError, 'Historical replay requires complete matching captured priors; legacy live values cannot seed replay'
    end
  end
end
