class CreateBookmakerOdds < ActiveRecord::Migration[7.1]
  def change
    create_table :bookmaker_odds do |t|
      t.references :game, foreign_key: true, null: false
      t.string :bookmaker, null: false
      t.datetime :fetched_at, null: false
      t.string :market, null: false # 'h2h', 'spreads', 'totals'
    
      t.string :team_name # from API
      t.string :team_side # 'home' or 'away'
    
      t.decimal :value # price, spread, or total
      t.integer :odds # american odds
    
      t.timestamps
    end
  end
end
