# frozen_string_literal: true

class AddLockTypeToGoodJobProcesses < ActiveRecord::Migration[8.0]
  def change
    reversible do |dir|
      dir.up do
        # Ensure this incremental update migration is idempotent
        # with monolithic install migration.
        return if connection.column_exists?(:good_job_processes, :lock_type)
      end
    end

    change_table :good_job_processes do |t|
      t.integer :lock_type, limit: 2
    end
  end
end
