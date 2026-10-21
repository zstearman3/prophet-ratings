# frozen_string_literal: true

class ScopeGameSyncDatesToProvider < ActiveRecord::Migration[8.1]
  def change
    add_column :game_sync_dates, :provider, :string, null: false, default: 'sports_reference'
    add_column :game_sync_dates, :contract_version, :string, null: false, default: 'legacy-unscoped'
    add_column :game_sync_dates, :semantic_profile, :string, null: false, default: 'sports-reference-legacy-v1'
    add_column :game_sync_dates, :adapter_revision, :string, null: false, default: 'legacy-unscoped'
    remove_index :game_sync_dates, [:season_id, :schedule_date], unique: true
    add_index :game_sync_dates, %i[season_id schedule_date provider contract_version semantic_profile adapter_revision],
              unique: true, name: 'index_game_sync_dates_on_provider_scope'
  end
end
