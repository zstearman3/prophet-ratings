# frozen_string_literal: true

# Retry only the selected provider game, with a pinned acquisition that redelivery cannot renew.
class RetryGameIngestionIssueJob < HeavyJob
  self.enqueue_after_transaction_commit = false
  rescue_from Ingestion::GameSyncProvider::Incomplete do |error|
    raise error
  end

  def perform(issue_id, acquisition_id)
    load_retry(issue_id, acquisition_id)
    with_retry_lock
  rescue HeavyJob::Contention
    raise
  rescue StandardError
    record_failure
    raise
  end

  private

  attr_reader :issue, :acquisition_id

  def load_retry(issue_id, acquisition_id)
    @issue = GameIngestionIssue.find(issue_id)
    @acquisition_id = acquisition_id
  end

  def record_failure
    issue&.update!(retry_status: 'failed') if issue&.retry_acquisition_id == acquisition_id
  end

  def with_retry_lock
    acquired = GoodJob::Job.advisory_lock_key("game-issue-retry:#{issue.id}") { [retry_source] }
    raise HeavyJob::Contention, 'Game issue retry is already running.' unless acquired
  end

  def retry_source
    issue.reload
    return unless issue.retry_acquisition_id == acquisition_id
    return if %w[completed completed_with_issues].include?(issue.retry_status)

    issue.update!(retry_status: 'running')
    import_result(acquired_row)
  end

  def acquired_row
    acquisition = issue.retry_acquisition
    Ingestion::Cbbd::ReviewAcquisition.new(acquisition).call
    replay = acquisition.reload.verified_sync_replay(issue.season, [issue.schedule_date])
    validate_replay(replay)
  end

  def validate_replay(replay)
    rows = replay.fetch('observations').select { |row| row['source_game_id'].to_s == issue.external_game_id }
    raise Ingestion::GameSyncProvider::Incomplete, { complete: false, issue_id: issue.id } unless replay['complete'] && rows.one?

    rows.sole
  end

  def import_result(row)
    Ingestion::GamesIngestionService.with_date_lock(issue.schedule_date) do
      report = Ingestion::HistoricalSyncObservation.new(row, issue.season).call
      status = Ingestion::GameSyncProvider.held?(report) ? 'completed_with_issues' : 'completed'
      issue.update!(retry_status: status)
    end
  end
end
