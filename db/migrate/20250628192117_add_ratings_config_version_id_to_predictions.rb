class AddRatingsConfigVersionIdToPredictions < ActiveRecord::Migration[7.1]
  ##
  # Adds a nullable foreign key reference to ratings_config_versions in the predictions table.
  def change
    add_reference :predictions, :ratings_config_version, null: true, foreign_key: true
  end
end
