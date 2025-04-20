# frozen_string_literal: true

require 'matrix'

module ProphetRatings
  class AdjustedStatCalculator
    def initialize(season:, raw_stat:, adj_stat:, adj_stat_allowed:)
      @season = season
      @raw_stat = raw_stat
      @adj_stat = adj_stat
      @adj_stat_allowed = adj_stat_allowed
    end

    def run
      Rails.logger.info("Starting adjustment: #{raw_stat} → #{adj_stat} / #{adj_stat_allowed}")
      season_avg = average_stat_for_season

      # Preload only teams with at least 2 games
      qualified_team_seasons = TeamSeason
        .includes(:team_games)
        .where(season: season)
        .select { |ts| ts.team_games.size >= 2 }

      team_ids = qualified_team_seasons.map(&:team_id)
      team_index = team_ids.each_with_index.to_h
      num_teams = team_ids.size

      rows = []
      b = []

      Rails.logger.info("Building adjustment matrix rows for #{num_teams} qualified teams...")

      qualified_team_seasons.each do |team_season|
        team_id = team_season.team_id
        team_index_val = team_index[team_id]

        team_season.team_games.each do |game|
          opponent = game.opponent_team_season
          next unless opponent&.season_id == season.id
          next unless team_index[opponent.team_id]

          observed =
          if raw_stat == :possessions
            game.game&.possessions
          else
            game.send(raw_stat)
          end
          next unless observed.present?

          row = Array.new(2 * num_teams, 0)
          row[team_index_val] = 1
          row[num_teams + team_index[opponent.team_id]] = 1

          rows << row
          b << (observed.to_f - season_avg)
        end
      end

      if rows.empty?
        Rails.logger.warn("No valid rows generated for #{raw_stat}")
        return
      end

      Rails.logger.info("Solving matrix with #{rows.size} rows and #{2 * num_teams} columns...")
      x_values = StatisticsUtils.solve_least_squares_with_python(rows, b)

      team_season_map = TeamSeason.where(season: season, team_id: team_ids).index_by(&:team_id)
      team_ids.each_with_index do |team_id, idx|
        ts = team_season_map[team_id]
        next unless ts
        
        stats_to_write = 
          if raw_stat == :possessions
            {
              adj_stat => (x_values[idx] + season_avg),
            }
          else
            {
              adj_stat => (x_values[idx] + season_avg),
              adj_stat_allowed => (x_values[num_teams + idx] + season_avg),
            }
          end
        ts.update!(stats_to_write)
      end

      Rails.logger.info("Adjustment complete for #{raw_stat}")
    end

    private

    attr_reader :season, :raw_stat, :adj_stat, :adj_stat_allowed

    def average_stat_for_season
      stat_to_avg = raw_stat == :possessions ? :pace : raw_stat
      TeamSeason.where(season:).average(stat_to_avg).to_f
    end
  end
end
