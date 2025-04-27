class CreateRatingsConfigVersions < ActiveRecord::Migration[7.1]
  def change
    create_table :ratings_config_versions do |t|
      t.jsonb :config, null: false
      t.string :description
      t.string :name, null: false, index: { unique: true }
      t.timestamps
    end
  end
end
