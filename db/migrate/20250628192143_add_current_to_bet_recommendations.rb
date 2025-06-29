class AddCurrentToBetRecommendations < ActiveRecord::Migration[7.1]
  def change
    add_column :bet_recommendations, :current, :boolean, default: false
    add_index :bet_recommendations, [:game_id, :bet_type], unique: true, where: "current IS TRUE", name: "index_bet_recommendations_on_game_and_type_current_true"
  end
end
