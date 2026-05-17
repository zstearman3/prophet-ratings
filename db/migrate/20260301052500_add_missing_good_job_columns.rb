# frozen_string_literal: true

class AddMissingGoodJobColumns < ActiveRecord::Migration[8.0]
  def up
    add_column :good_jobs, :locked_by_id, :uuid unless connection.column_exists?(:good_jobs, :locked_by_id)
    add_column :good_jobs, :locked_at, :datetime unless connection.column_exists?(:good_jobs, :locked_at)

    unless connection.column_exists?(:good_job_executions, :error_backtrace)
      add_column :good_job_executions, :error_backtrace, :text, array: true
    end

    add_column :good_job_executions, :process_id, :uuid unless connection.column_exists?(:good_job_executions, :process_id)
    add_column :good_job_executions, :duration, :interval unless connection.column_exists?(:good_job_executions, :duration)
  end

  def down
    remove_column :good_jobs, :locked_by_id if connection.column_exists?(:good_jobs, :locked_by_id)
    remove_column :good_jobs, :locked_at if connection.column_exists?(:good_jobs, :locked_at)
    remove_column :good_job_executions, :error_backtrace if connection.column_exists?(:good_job_executions, :error_backtrace)
    remove_column :good_job_executions, :process_id if connection.column_exists?(:good_job_executions, :process_id)
    remove_column :good_job_executions, :duration if connection.column_exists?(:good_job_executions, :duration)
  end
end
