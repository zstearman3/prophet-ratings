class AddAdjustedStatAveragesToSeasons < ActiveRecord::Migration[7.1]
  def change
    change_table :seasons, bulk: true do |t|
      # Efficiencies
      t.decimal :avg_adj_offensive_efficiency, precision: 6, scale: 3
      t.decimal :stddev_adj_offensive_efficiency, precision: 6, scale: 3

      t.decimal :avg_adj_defensive_efficiency, precision: 6, scale: 3
      t.decimal :stddev_adj_defensive_efficiency, precision: 6, scale: 3

      # Four Factors – Offense
      t.decimal :avg_adj_effective_fg_percentage, precision: 6, scale: 5
      t.decimal :stddev_adj_effective_fg_percentage, precision: 6, scale: 5

      t.decimal :avg_adj_turnover_rate, precision: 6, scale: 5
      t.decimal :stddev_adj_turnover_rate, precision: 6, scale: 5

      t.decimal :avg_adj_offensive_rebound_rate, precision: 6, scale: 5
      t.decimal :stddev_adj_offensive_rebound_rate, precision: 6, scale: 5

      t.decimal :avg_adj_free_throw_rate, precision: 6, scale: 5
      t.decimal :stddev_adj_free_throw_rate, precision: 6, scale: 5

      # Four Factors – Defense
      t.decimal :avg_adj_effective_fg_percentage_allowed, precision: 6, scale: 5
      t.decimal :stddev_adj_effective_fg_percentage_allowed, precision: 6, scale: 5

      t.decimal :avg_adj_turnover_rate_forced, precision: 6, scale: 5
      t.decimal :stddev_adj_turnover_rate_forced, precision: 6, scale: 5

      t.decimal :avg_adj_defensive_rebound_rate, precision: 6, scale: 5
      t.decimal :stddev_adj_defensive_rebound_rate, precision: 6, scale: 5

      t.decimal :avg_adj_free_throw_rate_allowed, precision: 6, scale: 5
      t.decimal :stddev_adj_free_throw_rate_allowed, precision: 6, scale: 5
    end
  end
end
