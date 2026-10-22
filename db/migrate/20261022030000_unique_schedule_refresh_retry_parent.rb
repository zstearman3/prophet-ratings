# frozen_string_literal: true

class UniqueScheduleRefreshRetryParent < ActiveRecord::Migration[8.1]
  def change
    remove_index :schedule_refresh_runs, column: :retry_of_id
    add_index :schedule_refresh_runs, :retry_of_id, unique: true
  end
end
