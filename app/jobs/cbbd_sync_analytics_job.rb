# frozen_string_literal: true

# Scoped recovery avoids another asynchronous handoff between ratings and predictions.
class CbbdSyncAnalyticsJob < HeavyJob
  self.enqueue_after_transaction_commit = false

  def initialize(*arguments)
    super
    @run = nil
  end

  def perform(run_id)
    @run = CbbdSyncRun.find(run_id)
    execute_locked
  rescue StandardError => error
    @run&.update!(analytics_error: error.class.name)
    raise
  end

  private

  def execute_locked
    acquired = GoodJob::Job.advisory_lock_key("cbbd-sync:#{@run.id}") do
      Season.with_ratings_lock { execute }
      true
    end
    raise Season::OperationInProgress, 'Scheduled run busy' unless acquired
  end

  def execute
    @run.reload
    return if %w[completed stale].include?(@run.analytics_status)
    return unless @run.past_status == 'completed' && authorized?

    calculate unless ratings_completed?
    predict if ready_to_predict?
  end

  def ratings_completed?
    @run.analytics_status == 'ratings_completed'
  end

  def ready_to_predict?
    ratings_completed? && authorized?
  end

  def authorized?
    return true if @run.current_authorization?

    @run.update!(analytics_status: 'stale')
    false
  end

  def calculate
    @run.transaction(requires_new: true) do
      version = UpdateRankingsJob.recalculate(@run.season, @run.ratings_config_version_id, sync_schedule_date: @run.schedule_date)
      @run.update!(analytics_status: version ? 'ratings_completed' : 'stale', analytics_error: nil)
    end
  end

  def predict
    @run.transaction(requires_new: true) do
      GenerateNightlyPredictionsJob.new.perform(@run.season_id, ratings_config_version_id: @run.ratings_config_version_id)
      @run.update!(analytics_status: 'completed', analytics_error: nil)
    end
  end
end
