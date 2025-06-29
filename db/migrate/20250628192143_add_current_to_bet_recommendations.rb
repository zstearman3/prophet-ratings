class AddCurrentToBetRecommendations < ActiveRecord::Migration[7.1]
  def change
    add_column :bet_recommendations, :current, :boolean, default: false
    add_index :bet_recommendations, :current, unique: true, where: "current IS TRUE"
  end
end
