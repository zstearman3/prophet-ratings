class AddRatingsConfigVersionIdToBetRecommendations < ActiveRecord::Migration[7.1]
  ##
  # Adds a nullable foreign key reference to ratings_config_version in the bet_recommendations table.
  def change
    add_reference :bet_recommendations, :ratings_config_version, null: true, foreign_key: true
  end
end
