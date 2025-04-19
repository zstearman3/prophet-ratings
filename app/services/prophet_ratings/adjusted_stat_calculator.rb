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
      team_ids = TeamSeason.where(season:).pluck(:team_id).uniq
      team_index = team_ids.each_with_index.to_h
      num_teams = team_ids.size

      rows = []
      b = []

      season_avg = average_stat_for_season

      TeamGame.includes(:team_season, :opponent_team_season)
              .where(team_seasons: { season_id: season.id })
              .find_each do |game|
        team_id = game.team_id
        opponent_id = game.opponent_team_season&.team_id

        next unless team_index[team_id] && team_index[opponent_id]

        observed = game.send(raw_stat)
        next unless observed.present?

        row = Array.new(2 * num_teams, 0)
        row[team_index[team_id]] = 1
        row[num_teams + team_index[opponent_id]] = 1

        rows << row
        b << (observed.to_f - season_avg)
      end

      return if rows.empty?

      a_matrix = Matrix.rows(rows)
      b_vector = Vector.elements(b)

      x_vector = (a_matrix.t * a_matrix).inverse * a_matrix.t * b_vector

      team_ids.each_with_index do |team_id, idx|
        ts = TeamSeason.find_by(team_id:, season_id: season.id)
        ts.update!(
          adj_stat => (x_vector[idx] + season_avg),
          adj_stat_allowed => (x_vector[num_teams + idx] + season_avg)
        )
      end
    end

    private

    attr_reader :season, :raw_stat, :adj_stat, :adj_stat_allowed

    def average_stat_for_season
      TeamSeason.where(season:).average(raw_stat).to_f
    end
  end
end
