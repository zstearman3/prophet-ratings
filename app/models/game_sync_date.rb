# frozen_string_literal: true

# Completion means a recognized source date was ingested, not that all games finalized.
class GameSyncDate < ApplicationRecord
  belongs_to :season

  validates :schedule_date, presence: true, uniqueness: { scope: :season_id }
  validates :status, inclusion: { in: %w[pending failed completed] }

  def completed?
    status == 'completed'
  end

  def begin_attempt
    update!(status: 'pending', attempts: attempts + 1, last_attempt_at: Time.current,
            completed_at: nil, imported_rows: nil)
  end

  def complete(result)
    update!(status: 'completed', completed_at: Time.current, imported_rows: result.fetch(:imported_rows))
  end

  def record_failure(message)
    update!(status: 'failed', last_error: message)
  end
end
