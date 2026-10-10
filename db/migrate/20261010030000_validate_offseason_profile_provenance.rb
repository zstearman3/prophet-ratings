# frozen_string_literal: true

class ValidateOffseasonProfileProvenance < ActiveRecord::Migration[8.1]
  def up
    duplicates = select_values('SELECT team_season_id FROM team_offseason_profiles GROUP BY team_season_id HAVING COUNT(*) > 1')
    if duplicates.any?
      raise ActiveRecord::MigrationError, "Conflicting offseason profiles for TeamSeason IDs #{duplicates.inspect}. " \
                                          'Review all evidence and deliberately resolve duplicates before retrying; no rows were changed.'
    end

    change_table :team_offseason_profiles, bulk: true do |table|
      table.text :source_reference
      table.date :observed_on
      table.jsonb :input_units, default: {}, null: false
      table.text :manual_adjustment_reason
    end
    remove_index :team_offseason_profiles, :team_season_id
    add_index :team_offseason_profiles, :team_season_id, unique: true
    add_reference :seasons, :preseason_revision, foreign_key: { to_table: :ratings_config_versions }
  end

  def down
    remove_reference :seasons, :preseason_revision, foreign_key: { to_table: :ratings_config_versions }
    remove_index :team_offseason_profiles, :team_season_id
    add_index :team_offseason_profiles, :team_season_id
    change_table :team_offseason_profiles, bulk: true do |table|
      table.remove :source_reference, :observed_on, :input_units, :manual_adjustment_reason
    end
  end
end
