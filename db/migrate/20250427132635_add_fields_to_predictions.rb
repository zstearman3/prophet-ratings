class AddFieldsToPredictions < ActiveRecord::Migration[7.1]
  def change
    add_reference :predictions, :home_team_snapshot, foreign_key: { to_table: :team_rating_snapshots }
    add_reference :predictions, :away_team_snapshot, foreign_key: { to_table: :team_rating_snapshots }
    add_column :predictions, :home_win_probability, :decimal, precision: 5, scale: 4
    add_column :predictions, :vegas_spread, :decimal, precision: 6, scale: 3
    add_column :predictions, :vegas_total, :decimal, precision: 6, scale: 3
  end
end
