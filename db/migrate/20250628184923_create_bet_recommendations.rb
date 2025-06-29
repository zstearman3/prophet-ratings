class CreateBetRecommendations < ActiveRecord::Migration[7.1]
  def change
    create_table :bet_recommendations do |t|
      t.references :game, null: false, foreign_key: true
      t.references :prediction, null: false, foreign_key: true
      t.references :game_odd, null: false, foreign_key: true
      t.string  :bet_type, null: false, comment: "'moneyline', 'spread', or 'total'"
      t.string  :team, null: false, comment: "'home', 'away', 'over', 'under'"
      t.float   :vegas_line, comment: 'point spread or total; nil for moneyline'
      t.integer :vegas_odds, null: false, comment: 'payout in American odds (e.g. -110, +150)'
      t.float   :model_value, null: false, comment: 'model-predicted value (spread, total, or win %)' 
      t.float   :ev, null: false, comment: 'expected value (unit-neutral, e.g. +0.07 = +7%)'
      t.float   :confidence, comment: 'optional: model confidence (0.0–1.0 or 0–100 scale)'
      t.boolean :recommended, null: false, default: false, comment: 'whether the bet is actionable'
      t.string  :result, comment: "'win', 'loss', 'push'"
      t.float   :payout, comment: 'net return in units, e.g. +0.91, -1.00'

      t.timestamps
    end
  end
end
