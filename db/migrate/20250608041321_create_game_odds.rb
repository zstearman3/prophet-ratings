class CreateGameOdds < ActiveRecord::Migration[7.1]
  def change
    create_table :game_odds do |t|
      t.references :game, foreign_key: true, null: false
      t.datetime :fetched_at, null: false
    
      t.integer :moneyline_home
      t.integer :moneyline_away
    
      t.decimal :spread_point
      t.integer :spread_home_odds
      t.integer :spread_away_odds
    
      t.decimal :total_points
      t.integer :total_over_odds
      t.integer :total_under_odds
    
      t.timestamps
    end
  end
end
