class AddRatingsConfigVersionIdToPredictions < ActiveRecord::Migration[7.1]
  def change
    add_reference :predictions, :ratings_config_version, null: true, foreign_key: true
  end
end
