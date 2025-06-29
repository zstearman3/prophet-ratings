class AddRatingsConfigVersionIdToBetRecommendations < ActiveRecord::Migration[7.1]
  def change
    add_reference :bet_recommendations, :ratings_config_version, null: true, foreign_key: true
  end
end
