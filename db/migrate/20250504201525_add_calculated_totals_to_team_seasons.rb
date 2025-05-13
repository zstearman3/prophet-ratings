class AddCalculatedTotalsToTeamSeasons < ActiveRecord::Migration[7.1]
  def change
    change_table :team_seasons, bulk: true do |t|
      t.decimal :total_home_boost, precision: 6, scale: 3
      t.decimal :total_volatility, precision: 6, scale: 3
    end
  end
end
