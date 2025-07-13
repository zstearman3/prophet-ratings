class AddUniqueIndexToBetRecommendations < ActiveRecord::Migration[7.0]
  def change
    add_index :bet_recommendations, [:prediction_id, :game_odd_id, :bet_type], unique: true, name: 'index_bet_recommendations_on_prediction_game_odd_bet_type'
  end
end
