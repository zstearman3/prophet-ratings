# frozen_string_literal: true

class AddHistoricalScheduleImports < ActiveRecord::Migration[8.1]
  def change
    change_table :schedule_refresh_runs, bulk: true do |table|
      table.string :mode, null: false, default: 'upcoming'
      table.boolean :rescan, null: false, default: false
    end
  end
end
