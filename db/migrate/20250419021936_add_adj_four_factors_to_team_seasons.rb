class AddAdjFourFactorsToTeamSeasons < ActiveRecord::Migration[7.1]
  def change
    change_table :team_seasons, bulk: true do |t|
      # Raw Four Factors
      t.decimal :efg_percentage, precision: 6, scale: 5
      t.decimal :turnover_rate, precision: 6, scale: 5
      t.decimal :offensive_rebound_rate, precision: 6, scale: 5
      t.decimal :free_throw_rate, precision: 6, scale: 5
      t.decimal :three_pt_attempt_rate, precision: 6, scale: 5

      # Adjusted Four Factors
      t.decimal :adj_effective_fg_percentage, precision: 6, scale: 5
      t.decimal :adj_effective_fg_percentage_allowed, precision: 6, scale: 5
      t.decimal :adj_turnover_rate, precision: 6, scale: 5
      t.decimal :adj_turnover_rate_forced, precision: 6, scale: 5
      t.decimal :adj_offensive_rebound_rate, precision: 6, scale: 5
      t.decimal :adj_defensive_rebound_rate, precision: 6, scale: 5
      t.decimal :adj_free_throw_rate, precision: 6, scale: 5
      t.decimal :adj_free_throw_rate_allowed, precision: 6, scale: 5
      t.decimal :adj_three_pt_attempt_rate, precision: 6, scale: 5
      t.decimal :adj_three_pt_attempt_rate_allowed, precision: 6, scale: 5

      # Home Court Advantage Factors
      t.decimal :home_offense_boost, precision: 6, scale: 3
      t.decimal :home_defense_boost, precision: 6, scale: 3
      t.decimal :away_offense_penalty, precision: 6, scale: 3
      t.decimal :away_defense_penalty, precision: 6, scale: 3
    end
  end
end
