# frozen_string_literal: true

# Sorts a supplied team-season relation using only columns rendered by the ratings table.
module RatingsTableSorting
  extend ActiveSupport::Concern

  TEAM_TABLE = Team.arel_table
  TEAM_SEASON_TABLE = TeamSeason.arel_table
  SORT_COLUMNS = {
    'school' => TEAM_TABLE[:school],
    'rating' => TEAM_SEASON_TABLE[:rating],
    'adj_offensive_efficiency' => TEAM_SEASON_TABLE[:adj_offensive_efficiency],
    'adj_defensive_efficiency' => TEAM_SEASON_TABLE[:adj_defensive_efficiency],
    'adj_pace' => TEAM_SEASON_TABLE[:adj_pace],
    'adj_turnover_rate' => TEAM_SEASON_TABLE[:adj_turnover_rate],
    'adj_turnover_rate_forced' => TEAM_SEASON_TABLE[:adj_turnover_rate_forced],
    'adj_offensive_rebound_rate' => TEAM_SEASON_TABLE[:adj_offensive_rebound_rate],
    'adj_defensive_rebound_rate' => TEAM_SEASON_TABLE[:adj_defensive_rebound_rate],
    'adj_free_throw_rate' => TEAM_SEASON_TABLE[:adj_free_throw_rate],
    'adj_three_pt_proficiency' => TEAM_SEASON_TABLE[:adj_three_pt_proficiency],
    'adj_three_pt_proficiency_allowed' => TEAM_SEASON_TABLE[:adj_three_pt_proficiency_allowed],
    'adj_effective_fg_percentage' => TEAM_SEASON_TABLE[:adj_effective_fg_percentage],
    'adj_effective_fg_percentage_allowed' => TEAM_SEASON_TABLE[:adj_effective_fg_percentage_allowed],
    'offensive_efficiency' => TEAM_SEASON_TABLE[:offensive_efficiency],
    'defensive_efficiency' => TEAM_SEASON_TABLE[:defensive_efficiency],
    'pace' => TEAM_SEASON_TABLE[:pace],
    'effective_fg_percentage' => TEAM_SEASON_TABLE[:effective_fg_percentage],
    'free_throw_rate' => TEAM_SEASON_TABLE[:free_throw_rate],
    'three_pt_attempt_rate' => TEAM_SEASON_TABLE[:three_pt_attempt_rate],
    'offensive_rebound_rate' => TEAM_SEASON_TABLE[:offensive_rebound_rate],
    'turnover_rate' => TEAM_SEASON_TABLE[:turnover_rate],
    'home_offense_boost' => TEAM_SEASON_TABLE[:home_offense_boost],
    'home_defense_boost' => TEAM_SEASON_TABLE[:home_defense_boost],
    'total_home_boost' => TEAM_SEASON_TABLE[:total_home_boost],
    'offensive_efficiency_volatility' => TEAM_SEASON_TABLE[:offensive_efficiency_volatility],
    'defensive_efficiency_volatility' => TEAM_SEASON_TABLE[:defensive_efficiency_volatility],
    'pace_volatility' => TEAM_SEASON_TABLE[:pace_volatility],
    'offensive_efficiency_std_dev' => TEAM_SEASON_TABLE[:offensive_efficiency_std_dev],
    'defensive_efficiency_std_dev' => TEAM_SEASON_TABLE[:defensive_efficiency_std_dev]
  }.freeze

  private

  def ordered_team_seasons(relation)
    relation.references(:team).order(selected_sort_order, TEAM_SEASON_TABLE[:id].asc)
  end

  def ordered_conference_team_seasons(relation)
    order = Arel::Nodes::NullsLast.new(selected_sort_order)
    relation.references(:team).order(order, TEAM_SEASON_TABLE[:id].asc)
  end

  def selected_sort_order
    column, direction = sort_column_and_direction
    column.public_send(direction)
  end

  def sort_column_and_direction
    key, requested_direction = params.permit(:sort, :direction).values_at('sort', 'direction')
    column = SORT_COLUMNS.fetch(key.to_s, SORT_COLUMNS.fetch('rating'))
    direction = %w[asc desc].include?(requested_direction) ? requested_direction.to_sym : :desc
    [column, direction]
  end
end
