class AddCurrentToRatingsConfigVersions < ActiveRecord::Migration[7.1]
  def change
    add_column :ratings_config_versions, :current, :boolean, default: false
    add_index :ratings_config_versions, :current, unique: true, where: "current IS TRUE"
  end
end
