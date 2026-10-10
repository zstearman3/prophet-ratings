# frozen_string_literal: true

module ProphetRatings
  # Opening-period hypothetical forecasts on one common cohort, one row per game/candidate.
  class PreseasonComparisonSequence
    def initialize(season:, sources:, older_sources:, baselines:, version:)
      @context = { season:, sources:, older_sources:, baselines: }
      @version = version
    end

    def call(games)
      older = @context.fetch(:older_sources)
      observations = games.map(&:schedule_date).uniq.index_with { |date| observations_on(date) }
      {
        forecast_kind: 'retrospective reconstruction; not archived live forecasts',
        candidates: PreseasonComparisonCandidate::NAMES.index_with { |name| candidate_report(name, games, observations) },
        observations: observations.transform_keys(&:iso8601),
        second_year_snapshot_ids: older.values.map(&:id).sort,
        missing_second_year_teams: (@context.fetch(:sources).keys - older.keys).sort
      }
    end

    def self.in_cohort?(game, ids)
      ids.include?(game.home_team_game&.team_id) && ids.include?(game.away_team_game&.team_id)
    end

    def self.prior_count(game, history)
      [game.home_team_game&.team_id, game.away_team_game&.team_id].map do |id|
        team_count(id, game.schedule_date, history)
      end.min
    end

    def self.team_count(id, date, history)
      history.count { |past| past.schedule_date < date && [past.home_team_game&.team_id, past.away_team_game&.team_id].include?(id) }
    end

    def self.coverage(games, eligible, season)
      history = season.games.final.through_schedule_date(season.start_date + 29).includes(:home_team_game, :away_team_game).to_a
      groups = games.group_by { |game| prior_count(game, history) }
      groups.sort.to_h.transform_values { |members| coverage_counts(members, eligible) }
    end

    def self.coverage_counts(members, eligible)
      total = members.size
      included = (members & eligible).size
      { opening_final_games: total, eligible_games: included, excluded_games: total - included }
    end

    def self.group_metrics(rows)
      groups = rows.group_by { |row| row.fetch(:prior_games) }
      groups.sort.to_h.transform_values { |members| PreseasonComparisonMetrics.new(members).call }
    end

    private

    def observations_on(date)
      ids = @context.fetch(:sources).keys
      history = @context.fetch(:season).games.final.through_schedule_date(date - 1)
                        .includes(:season, :home_team_game, :away_team_game).order(:start_time, :id).to_a
      history.select! { |game| self.class.in_cohort?(game, ids) }
      PreseasonComparisonObservations.new(games: history, date:, version: @version).call
    end

    def candidate_report(name, games, observations)
      candidate = PreseasonComparisonCandidate.new(name, @version.config)
      rows = games.map { |game| prediction_row(game, { candidate:, state: observations.fetch(game.schedule_date) }) }
      PreseasonComparisonMetrics.new(rows).call.merge(
        forecasts: rows, by_prior_game_count: self.class.group_metrics(rows)
      )
    end

    def prediction_row(game, working)
      ids = [game.home_team_game&.team_id, game.away_team_game&.team_id]
      ratings = ids.index_with { |id| rating(id, working.merge(date: game.schedule_date)) }
      result = PreseasonComparisonSeason.predict(game, ratings, self.class.anchors(@version.config))
      PreseasonComparisonSeason.errors(game, result).merge(game_id: game.id,
                                                           prior_games: PreseasonComparisonSequence.minimum_count(
                                                             ids, working.fetch(:state)
                                                           ))
    end

    public_class_method def self.anchors(payload)
      config = payload.fetch('preseason')
      Season.new(average_efficiency: config.fetch('fallback_efficiency'), average_pace: config.fetch('fallback_pace'))
    end

    def rating(id, working)
      candidate = working.fetch(:candidate)
      source = @context.fetch(:sources).fetch(id)
      prior = candidate.prior(source, @context.fetch(:older_sources)[id], @context.fetch(:baselines))
      values = blended_values(id, prior, working)
      TeamRatingSnapshot.new(**values.symbolize_keys, team: source.team, ratings_config_version: @version,
                                                      stats: self.class.volatility(@version.config))
    end

    def blended_values(id, prior, working)
      self.class.blend(prior, id, working.merge(opening: @context.fetch(:season).start_date))
    end

    public_class_method def self.minimum_count(ids, state)
      ids.map { |id| state[:counts].fetch(id, 0) }.min
    end

    public_class_method def self.blend(prior, id, working)
      observed = working.fetch(:state)[:ratings][id]
      return prior unless observed

      weight = transition_weight(id, working)
      prior.to_h { |stat, value| [stat, (weight * value) + ((1 - weight) * observed.fetch(stat))] }
    end

    public_class_method def self.transition_weight(id, working)
      state = working.fetch(:state)
      working.fetch(:candidate).weight(days: (working.fetch(:date) - 1 - working.fetch(:opening)).to_i,
                                       games: state[:counts].fetch(id), effective_games: state[:effective_counts].fetch(id))
    end

    public_class_method def self.volatility(payload)
      config = payload.fetch('baseline_volatility')
      efficiency = config.fetch('efficiency_volatility')
      { offensive_efficiency_volatility: efficiency, defensive_efficiency_volatility: efficiency,
        pace_volatility: config.fetch('pace_volatility') }
    end
  end
end
