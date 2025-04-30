# frozen_string_literal: true

require 'matrix'

module ProphetRatings
  class AdjustedStatCalculator
    RATINGS_CONFIG = Rails.application.config_for(:ratings).deep_symbolize_keys

    def initialize(season:, raw_stat:, adj_stat:, adj_stat_allowed:, as_of: Time.current)
      @season = season
      @raw_stat = raw_stat
      @adj_stat = adj_stat
      @adj_stat_allowed = adj_stat_allowed
      @as_of = as_of
    end

    def call
      Rails.logger.info("Starting adjustment: #{raw_stat} → #{adj_stat} / #{adj_stat_allowed}")
      season_avg = average_stat_for_season

      # Preload only teams with at least 2 games
      qualified_team_seasons = TeamSeason
        .includes(team_games: :game)
        .where(season: season)
        .select { |ts| ts.team_games.size >= 2 }
        .sort_by(&:team_id)

      team_ids = qualified_team_seasons.map(&:team_id)
      team_index = team_ids.each_with_index.to_h
      num_teams = team_ids.size

      rows, b, weights, row_metadata = build_matrix_components(team_index, num_teams, season_avg)

      if rows.empty?
        Rails.logger.warn("No valid rows generated for #{raw_stat}")
        return
      end

      Rails.logger.info("Solving matrix with #{rows.size} rows and #{2 * num_teams} columns...")

      # --- Matrix Diagnostics ---
      b_mean = b.sum / b.size.to_f
      b_stddev = StatisticsUtils.stddev(b)
      Rails.logger.info("[Diagnostics] #{raw_stat}:")
      Rails.logger.info("  → Matrix rows: #{rows.size}")
      Rails.logger.info("  → Columns (teams x 2): #{2 * num_teams}")
      Rails.logger.info("  → b mean: #{b_mean.round(4)}")
      Rails.logger.info("  → b stddev: #{b_stddev.round(4)}")

      # Check for NaNs or Infs safely
      has_nan_or_inf = rows.flatten.map(&:to_f).any? { |v| v.nan? || v.infinite? } ||
        b.map(&:to_f).any? { |v| v.nan? || v.infinite? }

      if has_nan_or_inf
        Rails.logger.error("⚠️ Matrix contains NaN or Inf values! Stat=#{raw_stat}")
      end

      extreme_b_indices = b.each_index.select { |i| b[i].abs > 15 }

      extreme_b_indices.each do |i|
        meta = row_metadata[i]
        Rails.logger.warn(
          "[Extreme b] index=#{i}, adjusted=#{meta[:adjusted_observed]}, team_id=#{meta[:team_id]}, game_id=#{meta[:game_id]}, "\
          "raw=#{meta[:observed]}, home_court=#{meta[:home_court]}, possessions=#{meta[:raw_possessions]}, minutes=#{meta[:minutes]}"
        )
      end

      x_values = StatisticsUtils.solve_least_squares_with_python(rows, b, weights)

      team_season_map = TeamSeason.where(season: season, team_id: team_ids).index_by(&:team_id)
      team_ids.each_with_index do |team_id, idx|
        ts = team_season_map[team_id]
        next unless ts

        stats_to_write = build_stats_to_write(ts, x_values, season_avg, idx, num_teams)
        ts.update!(stats_to_write)
      end

      Rails.logger.info("Adjustment complete for #{raw_stat}")
    end

    private

    attr_reader :season, :raw_stat, :adj_stat, :adj_stat_allowed, :as_of

    def average_stat_for_season
      stat_to_avg = raw_stat == :possessions ? :pace : raw_stat
      TeamSeason.where(season:).average(stat_to_avg).to_f
    end

    def stat_value_for_game(team_game)
      if raw_stat == :possessions
        game = team_game.game
        return nil unless game

        pace = (game&.possessions * 40.0) / game.minutes
        return pace
      end
      
      team_game.send(raw_stat)
    end

    def blowout_dampening(team_game)
      return 1.0 unless %i[offensive_rating defensive_rating].include?(raw_stat)

      margin_cap = RATINGS_CONFIG[:blowout][:max_margin]
      multiplier = config[:cap_multiplier].to_f
      margin = if team_game.opponent_team_game&.points && team_game.points
        (team_game.points - team_game.opponent_team_game.points).abs
      else
        0
      end
      Math.tanh(multiplier * margin / margin_cap)
    end

    def blend_with_preseason(preseason_value, observed_value)
      return observed_value unless preseason_value.present?
      weight = preseason_weight
      (weight * preseason_value) + ((1 - weight) * observed_value)
    end

    def preseason_weight
      start_date = season.start_date
      days_since_start = (as_of.to_date - start_date).to_i
      decay_days = RATINGS_CONFIG[:weighting][:preseason_decay_days] || 30
      min_weight = RATINGS_CONFIG[:weighting][:min_preseason_weight] || 0.0
      [1.0 - (days_since_start.to_f / decay_days), min_weight].max.round(4)
    end

    def build_stats_to_write(ts, x_values, season_avg, idx, num_teams)
      offense_value = x_values[idx] + season_avg
      defense_value = x_values[num_teams + idx] + season_avg

      case raw_stat
      when :possessions
        { adj_stat => blend_with_preseason(ts.preseason_adj_pace, offense_value) }
      when :offensive_efficiency
        {
          adj_stat => blend_with_preseason(ts.preseason_adj_offensive_efficiency, offense_value),
          adj_stat_allowed => blend_with_preseason(ts.preseason_adj_defensive_efficiency, defense_value)
        }
      when :offensive_rebound_rate
        { adj_stat => offense_value, adj_stat_allowed => (1.0 - defense_value) }
      else
        { adj_stat => offense_value, adj_stat_allowed => defense_value }
      end
    end

    def build_matrix_components(team_index, num_teams, season_avg)
      rows = []
      b = []
      weights = []
      row_metadata = []  # Add this to collect game+team context

      hca_stats = Array(RATINGS_CONFIG[:home_court_adjusted_stats]).map(&:to_sym)
      home_adv = RATINGS_CONFIG[:home_court_advantage].to_f

      Game.where(season: season, status: :final, start_time: ..as_of).includes(:home_team_game, :away_team_game).find_each do |game|
        tg1 = game.home_team_game
        tg2 = game.away_team_game
        next unless tg1 && tg2
        next unless team_index[tg1.team_id] && team_index[tg2.team_id]

        apply_home_court = hca_stats.include?(raw_stat) && !game.neutral

        [ [tg1, tg2], [tg2, tg1] ].each do |off_tg, def_tg|
          observed = stat_value_for_game(off_tg)
          next unless observed.present?

          observed *= blowout_dampening(off_tg)

          home_court = if apply_home_court
             tg1 == off_tg ? home_adv : -home_adv
          else
            0.0
          end

          adjusted_observed = observed - home_court - season_avg

          row = Array.new(2 * num_teams, 0)
          row[team_index[off_tg.team_id]] = 1
          row[num_teams + team_index[def_tg.team_id]] = 1

          rows << row
          b << adjusted_observed.to_f
          weights << GameWeightingService.new(game: off_tg, season:, as_of:).call

          # ➕ Add metadata
          row_metadata << {
            game_id: off_tg.game_id,
            team_id: off_tg.team_id,
            observed: observed,
            adjusted_observed: adjusted_observed.round(2),
            home_court: home_court,
            raw_possessions: off_tg.game&.possessions,
            minutes: off_tg.game&.minutes
          }
        end
      end

      anchor_weight = RATINGS_CONFIG.dig(:anchor, :weight).to_f
      anchor_row = Array.new(2 * num_teams, 0.0)
      (0...num_teams).each { |i| anchor_row[i] = 1.0 }
      rows << anchor_row
      b << 0.0
      weights << anchor_weight

      [rows, b, weights, row_metadata]
    end
  end
end