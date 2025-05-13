class AddRanksToTeamSeasons < ActiveRecord::Migration[7.1]
  def change
    change_table :team_seasons, bulk: true do |t|
      t.integer :overall_rank
      t.integer :pace_rank
      t.integer :adj_offensive_efficiency_rank
      t.integer :adj_defensive_efficiency_rank

      t.integer :adj_effective_fg_percentage_rank
      t.integer :adj_turnover_rate_rank
      t.integer :adj_offensive_rebound_rate_rank
      t.integer :adj_free_throw_rate_rank

      t.integer :adj_effective_fg_percentage_allowed_rank
      t.integer :adj_turnover_rate_forced_rank
      t.integer :adj_defensive_rebound_rate_rank
      t.integer :adj_free_throw_rate_allowed_rank
    end
  end
end
