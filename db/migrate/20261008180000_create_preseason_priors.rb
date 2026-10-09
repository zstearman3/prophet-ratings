# frozen_string_literal: true

class CreatePreseasonPriors < ActiveRecord::Migration[8.1]
  def change
    create_table :preseason_priors do |t|
      t.references :team_season, null: false, foreign_key: true
      t.references :ratings_config_version, null: false, foreign_key: true
      t.jsonb :inputs, null: false
      t.jsonb :outputs, null: false
      t.timestamps
    end
    add_index :preseason_priors, %i[team_season_id ratings_config_version_id], unique: true,
                                                                               name: 'index_preseason_priors_on_team_season_and_config'
  end
end
