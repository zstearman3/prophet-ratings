# frozen_string_literal: true

module ProphetRatings
  # Effective season inputs belong to a model/date publication, not mutable live season state.
  class SeasonForecastInputs
    FALLBACKS = {
      'average_efficiency' => %i[defaults season_defaults average_efficiency],
      'average_pace' => %i[defaults season_defaults average_pace],
      'efficiency_std_deviation' => %i[baseline_volatility efficiency_volatility],
      'pace_std_deviation' => %i[baseline_volatility pace_volatility]
    }.freeze

    def self.capture(season, version, date)
      values = effective_values(season, version.settings)
      validate_values(values)
      day = date.to_date.iso8601
      { 'contract_version' => 1, 'model_version_id' => version.id, 'season_id' => season.id,
        'snapshot_date' => day, 'result_cutoff' => day, 'source' => 'publication',
        'values' => values, 'value_sources' => value_sources(season) }
    end

    def self.effective_values(season, config)
      FALLBACKS.to_h { |field, path| [field, (season.public_send(field) || config.dig(*path))&.to_f] }
    end

    def self.value_sources(season)
      FALLBACKS.to_h { |field, path| [field, season.public_send(field) ? 'season' : "config.#{path.join('.')}"] }
    end

    def self.reconstruction(team_season, date)
      capture(team_season.season, team_season.ratings_config_version, date).merge('source' => 'reconstruction')
    end

    def self.for_snapshots(game, snapshots, version)
      participants = participants_for(game, snapshots)
      inputs = snapshots.zip(participants).map { |snapshot, participant| validated_inputs(snapshot, participant, version) }
      validate_pair(inputs, game)
      inputs.first.deep_dup
    end

    def self.validate_pair(inputs, game)
      first, second = inputs
      raise ArgumentError, 'Season forecast inputs must match across both model/date publication sources' unless first == second
      return unless first['snapshot_date'] >= game.schedule_date.iso8601

      raise ArgumentError, 'Season forecast inputs cutoff must precede the Eastern game date'
    end

    def self.participants_for(game, snapshots)
      participants = [game.home_team_season, game.away_team_season]
      unless snapshots.size == 2 && participants.all? { |participant| participant&.season_id == game.season_id }
        raise ArgumentError, 'Season forecast inputs require both prepared participants in the game season'
      end

      participants
    end

    def self.validated_inputs(snapshot, participant, version)
      validate_snapshot(snapshot, participant, version)
      saved = snapshot.stats['season_forecast_inputs']
      validate_metadata(saved, snapshot)
      saved
    end

    def self.validate_snapshot(snapshot, participant, version)
      return if snapshot && snapshot.team_id == participant.team_id && snapshot.team_season_id == participant.id &&
                snapshot.season_id == participant.season_id && snapshot.ratings_config_version_id == version.id

      raise ArgumentError, 'Season forecast inputs snapshot must match selected model, season and game participant'
    end

    def self.validate_metadata(saved, snapshot)
      date = snapshot.snapshot_date&.iso8601
      unless date && saved.is_a?(Hash) && saved['contract_version'] == 1 &&
             saved['model_version_id'] == snapshot.ratings_config_version_id && saved['season_id'] == snapshot.season_id &&
             saved.values_at('snapshot_date', 'result_cutoff') == [date, date] && saved['source'] == source_for(snapshot)
        raise ArgumentError, 'Missing or incompatible season forecast inputs; republish ratings for the selected model/date'
      end

      validate_values(saved['values'])
      validate_sources(saved['value_sources'])
    end

    def self.source_for(snapshot)
      snapshot.persisted? ? 'publication' : 'reconstruction'
    end

    def self.validate_values(values)
      return if values.is_a?(Hash) && values.keys.sort == FALLBACKS.keys.sort && values.all? do |field, value|
        value.is_a?(Numeric) && value.finite? && (field.start_with?('average_') ? value.positive? : value >= 0)
      end

      raise ArgumentError, 'Season forecast inputs require finite positive means and nonnegative deviations'
    end

    def self.validate_sources(sources)
      return if sources.is_a?(Hash) && sources.keys.sort == FALLBACKS.keys.sort && sources.all? do |field, source|
        ['season', "config.#{FALLBACKS.fetch(field).join('.')}"].include?(source)
      end

      raise ArgumentError, 'Season forecast inputs require explicit season or configured fallback evidence'
    end
  end
end
