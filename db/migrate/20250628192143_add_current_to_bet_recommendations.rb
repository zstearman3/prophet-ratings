class AddCurrentToBetRecommendations < ActiveRecord::Migration[7.1]
  ##
  # Adds a boolean `current` column to the `bet_recommendations` table with a default of `false`, and creates a unique partial index on `game_id` and `bet_type` where `current` is `true`.
  def change
    add_column :bet_recommendations, :current, :boolean, default: false
    add_index :bet_recommendations, [:game_id, :bet_type], unique: true, where: "current IS TRUE", name: "index_bet_recommendations_on_game_and_type_current_true"
  end
end
