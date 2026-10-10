# frozen_string_literal: true

module ProphetRatings
  # Snapshotless D-1 state rebuilt from timestamp-eligible prepared results, without writes or residual learning.
  class PreseasonComparisonObservations
    def initialize(games:, date:, version:)
      @context = { games:, date:, version: }
      @eligible = games.select { |game| eligible?(game) }
      @sides = @eligible.flat_map { |game| self.class.sides(game) }.group_by(&:team_id)
    end

    def ids
      @context[:ids] ||= qualified_sides.map(&:team_id).uniq.sort
    end

    def qualified_games
      qualifying = @sides.select { |_id, sides| sides.size >= 2 }.keys
      @eligible.select { |game| PreseasonComparisonSequence.in_cohort?(game, qualifying) }
    end

    def call
      {
        counts: @sides.transform_values(&:size), effective_counts: @sides.transform_values { |sides| effective_count(sides) },
        ratings: solve, result_game_ids: @eligible.map(&:id).sort,
        excluded_result_game_ids: (@context.fetch(:games) - @eligible).map(&:id).sort
      }
    end

    def self.sides(game)
      [game.home_team_game, game.away_team_game]
    end

    def self.positive?(value)
      value.is_a?(Numeric) && value.finite? && value.positive?
    end

    def self.value(side, stat)
      { pace: side.game.pace, offensive_efficiency: side.offensive_efficiency }.fetch(stat).to_f
    end

    def self.mean(sides, stat)
      StatisticsUtils.average(sides.map { |side| value(side, stat) })
    end

    def self.row(ids, side)
      game = side.game
      team_id = side.team_id
      opponent = ([game.home_team_game&.team_id, game.away_team_game&.team_id] - [team_id]).first
      build_row(ids.size, ids.index(team_id), ids.index(opponent))
    end

    def self.build_row(size, index, opponent)
      Array.new(2 * size) { |column| [index, size + opponent].include?(column) ? 1.0 : 0.0 }
    end

    def self.available?(records, cutoff)
      records.all? { |record| record && record.created_at < cutoff && record.updated_at < cutoff }
    end

    private

    def eligible?(game)
      date = @context.fetch(:date)
      return false unless game.final? && game.schedule_date < date

      sides = self.class.sides(game)
      cutoff = Game.schedule_day_range(date).begin
      PreseasonComparisonObservations.available?([game, *sides], cutoff) &&
        PreseasonComparisonSeason.valid_outcome?(game) && PreseasonComparisonObservations.valid_stats?(game, sides)
    end

    public_class_method def self.valid_stats?(game, sides)
      positive?(game.pace) && sides.all? { |side| PreseasonComparisonObservations.positive?(side.offensive_efficiency) }
    end

    def recency(side)
      GameWeightingService.new(game: side, season: side.game.season, as_of: @context.fetch(:date) - 1,
                               ratings_config_version: @context.fetch(:version)).call
    end

    def effective_count(sides)
      sides.sum { |side| recency(side) }
    end

    def qualified_sides
      @context[:qualified_sides] ||= qualified_games.flat_map { |game| self.class.sides(game) }
    end

    def solve
      return {} if qualified_sides.empty?

      efficiency = solve_stat(:offensive_efficiency)
      pace = solve_stat(:pace)
      ids.each_with_index.to_h do |id, index|
        [id, { 'adj_offensive_efficiency' => efficiency[index], 'adj_defensive_efficiency' => efficiency[ids.size + index],
               'adj_pace' => pace[index] }]
      end
    end

    def average(stat)
      StatisticsUtils.average(@sides.values.map { |sides| self.class.mean(sides, stat) })
    end

    def solve_stat(stat)
      mean = average(stat)
      components = matrix(stat, mean)
      StatisticsUtils.solve_least_squares_with_python(components.fetch(:rows), components.fetch(:targets),
                                                      weights: components.fetch(:weights), ridge_alpha: config.dig('ridge', 'alpha'))
                     .map { |coefficient| coefficient + mean }
    end

    def matrix(stat, mean)
      components = qualified_sides.map { |side| matrix_side(side, stat, mean) }.transpose
      size = ids.size
      { rows: (components[0] || []) + [Array.new(size, 1.0) + Array.new(size, 0.0)],
        targets: (components[1] || []) + [0.0], weights: (components[2] || []) + [config.dig('anchor', 'weight')] }
    end

    def matrix_side(side, stat, mean)
      [self.class.row(ids, side), PreseasonComparisonObservations.value(side, stat) - home_adjustment(side, stat) - mean, recency(side)]
    end

    def config
      @context.fetch(:version).config
    end

    def home_adjustment(side, stat)
      game = side.game
      return 0.0 unless config.fetch('home_court_adjusted_stats').include?(stat.to_s) && game.confirmed_home_venue?

      config.fetch('home_court_advantage') * (side.team_id == game.home_team_game&.team_id ? 1 : -1)
    end
  end
end
