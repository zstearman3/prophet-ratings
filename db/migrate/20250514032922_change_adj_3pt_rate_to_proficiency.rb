class ChangeAdj3ptRateToProficiency < ActiveRecord::Migration[7.1]
  def change
    remove_column :team_seasons, :adj_three_pt_attempt_rate, :decimal
    remove_column :team_seasons, :adj_three_pt_attempt_rate_allowed, :decimal
    remove_column :team_seasons, :adj_three_pt_attempt_rate_rank, :decimal
    remove_column :team_seasons, :adj_three_pt_attempt_rate_allowed_rank, :decimal

    add_column :team_seasons, :adj_three_pt_proficiency, :decimal, precision: 6, scale: 5
    add_column :team_seasons, :adj_three_pt_proficiency_allowed, :decimal, precision: 6, scale: 5
    add_column :team_seasons, :adj_three_pt_proficiency_rank, :integer
    add_column :team_seasons, :adj_three_pt_proficiency_allowed_rank, :integer
    
    add_column :seasons, :avg_adj_three_pt_proficiency, :decimal, precision: 6, scale: 5
    add_column :seasons, :stddev_adj_three_pt_proficiency, :decimal, precision: 6, scale: 5

    add_column :team_games, :three_pt_proficiency, :decimal, precision: 6, scale: 5
  end
end
