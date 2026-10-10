# frozen_string_literal: true

module ProphetRatings
  # Evaluates one opening month from timestamp-eligible previous-season snapshots.
  class PreseasonComparisonSeason
    def initialize(season:, source_version:, ratings_config_version:)
      @ratings_config_version = ratings_config_version
      @season = season
      @source_version = source_version
      @data = {}
    end

    def call
      total = games.size
      count = eligible.size
      {
        year: @season.year, source_teams: sources.size, opening_final_games: total,
        eligible_games: count, excluded_games: total - count,
        exclusion: 'Missing pre-opening previous-season snapshots, teams, venue evidence, or untied final scores',
        source_snapshot_ids: sources.values.map(&:id).sort,
        candidates: PreseasonComparison::CANDIDATE_WEIGHTS.index_with { |weight| candidate_report(weight) },
        sequential: sequence_report,
        coverage_by_prior_game_count: PreseasonComparisonSequence.coverage(games, eligible, @season)
      }
    end

    def sequence_report
      older = transition_snapshots(@season.year - 2).each_with_object({}) do |snapshot, result|
        result[snapshot.team_id] ||= snapshot if self.class.finite_ratings?(snapshot)
      end
      PreseasonComparisonSequence.new(season: @season, sources:, older_sources: older, baselines:,
                                      version: @ratings_config_version).call(eligible)
    end

    def sources
      @data[:sources] ||= transition_snapshots.each_with_object({}) do |snapshot, result|
        next unless self.class.finite_ratings?(snapshot)

        result[snapshot.team_id] ||= snapshot
      end
    end

    def transition_snapshots(year = @season.year - 1)
      previous = Season.find_by(year:)
      last = previous&.end_date
      return TeamRatingSnapshot.none unless last && last < opening_date

      cutoff = Game.schedule_day_range(opening_date).begin
      TeamRatingSnapshot.where(season: previous, ratings_config_version: @source_version)
                        .where(snapshot_date: (last - 30)..last)
                        .where('created_at < ? AND updated_at < ?', cutoff, cutoff)
                        .order(snapshot_date: :desc, id: :desc)
    end

    def self.finite_ratings?(snapshot)
      PreseasonPriorFormula::STATS.all? { |stat| snapshot.public_send(stat)&.finite? }
    end

    def games
      @data[:games] ||= @season.games.final
                               .where(start_time: Game.schedule_day_range(opening_date).begin..opening_end)
                               .includes(:home_team, :away_team, :home_team_game, :away_team_game).order(:start_time, :id).to_a
    end

    def opening_date
      @season.start_date
    end

    def opening_end
      Game.schedule_day_range([opening_date + 29, @season.end_date].min).end
    end

    def eligible
      @data[:eligible] ||= games.select do |game|
        self.class.valid_outcome?(game) && sources.key?(game.home_team&.id) && sources.key?(game.away_team&.id)
      end
    end

    def self.valid_outcome?(game)
      scores = [game.home_team_score, game.away_team_score]
      scores.none?(&:nil?) && scores.uniq.size == 2 && (game.venue_neutral? || game.confirmed_home_venue?)
    end

    def candidate_report(weight)
      ratings = candidate_ratings(weight)
      season = Season.new(average_efficiency: configured('preseason', 'fallback_efficiency'),
                          average_pace: configured('preseason', 'fallback_pace'))
      rows = eligible.map do |game|
        PreseasonComparisonSeason.errors(game, PreseasonComparisonSeason.predict(game, ratings, season))
      end
      PreseasonComparisonMetrics.new(rows).call
    end

    def candidate_ratings(weight)
      candidate = @ratings_config_version.config.deep_dup
      candidate.fetch('preseason')['previous_season_weight'] = weight
      sources.transform_values { |snapshot| candidate_snapshot(snapshot, candidate) }
    end

    def baselines
      @data[:baselines] ||= PreseasonPriorFormula::STATS.index_with do |stat|
        PreseasonComparisonCandidate.source_mean(sources.values, stat)
      end
    end

    def candidate_snapshot(snapshot, candidate)
      inputs = { baselines:, previous_values: snapshot.attributes.slice(*PreseasonPriorFormula::STATS), profile_values: {} }
      outputs = PreseasonPriorFormula.new(inputs, candidate).call.transform_keys { |stat| stat.delete_prefix('preseason_') }
      TeamRatingSnapshot.new(**outputs, team: snapshot.team, stats: volatility_defaults, ratings_config_version: @ratings_config_version)
    end

    def volatility_defaults
      efficiency = configured('baseline_volatility', 'efficiency_volatility')
      {
        offensive_efficiency_volatility: efficiency,
        defensive_efficiency_volatility: efficiency,
        pace_volatility: configured('baseline_volatility', 'pace_volatility')
      }
    end

    def self.predict(game, ratings, season)
      GamePredictor.new(home_rating_snapshot: ratings.fetch(game.home_team.id),
                        away_rating_snapshot: ratings.fetch(game.away_team.id),
                        venue: { type: game.venue_type, confidence: game.venue_confidence },
                        season:).call
    end

    def configured(section, key)
      @ratings_config_version.config.fetch(section).fetch(key)
    end

    def self.errors(game, result)
      home_error = result.fetch(:home_expected_score) - game.home_team_score
      away_error = result.fetch(:away_expected_score) - game.away_team_score
      {
        margin_error: home_error - away_error,
        total_error: home_error + away_error,
        efficiency_errors: [game.home_team_game, game.away_team_game].zip(
          [result.dig(:meta, :home_expected_ortg), result.dig(:meta, :away_expected_ortg)]
        ).filter_map { |side, expected| expected - side.offensive_efficiency if side&.offensive_efficiency&.finite? },
        pace_errors: PreseasonComparisonMetrics.pace_errors(game.pace, result.dig(:meta, :expected_pace)),
        probability: result.fetch(:win_probability_home), outcome: game.winning_team == game.home_team ? 1.0 : 0.0
      }
    end
    private :sequence_report, :sources, :transition_snapshots, :games, :opening_date, :opening_end, :eligible,
            :candidate_report, :candidate_ratings, :baselines, :candidate_snapshot,
            :volatility_defaults
  end
end
