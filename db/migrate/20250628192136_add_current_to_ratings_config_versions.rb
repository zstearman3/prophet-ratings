class AddCurrentToRatingsConfigVersions < ActiveRecord::Migration[7.1]
  ##
  # Adds a boolean 'current' column to the ratings_config_versions table with a default of false,
  # and creates a unique partial index on rows where 'current' is true.
  def change
    add_column :ratings_config_versions, :current, :boolean, default: false
    add_index :ratings_config_versions, :current, unique: true, where: "current IS TRUE"
  end
end
