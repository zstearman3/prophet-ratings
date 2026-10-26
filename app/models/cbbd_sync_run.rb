# frozen_string_literal: true

# A scheduled delivery retains its original scope and finite acquisition budgets.
class CbbdSyncRun < ApplicationRecord
  belongs_to :season
  belongs_to :ratings_config_version
  belongs_to :past_acquisition, class_name: 'CbbdReviewRun', optional: true
  belongs_to :future_acquisition, class_name: 'CbbdReviewRun', optional: true

  before_validation :pin_season_bounds, on: :create

  attr_readonly :season_start_date, :season_end_date, :season_id, :ratings_config_version_id, :schedule_date, :bucket, :maximum_requests,
                :retries
  validates :schedule_date, :bucket, :season_start_date, :season_end_date, presence: true
  validates :maximum_requests, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 10_000 }
  validates :retries, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }

  def self.pin_current
    season = Season.current
    today = Game.current_schedule_date
    return unless season && ((season.start_date - 7)..(season.end_date + 1)).cover?(today)

    create_or_find_by!(season:, bucket: current_bucket) { |run| run.assign_attributes(pinned_attributes(today)) }
  end

  def self.current_bucket
    eastern = Time.current.in_time_zone('America/New_York')
    eastern.change(hour: (eastern.hour / 6) * 6, min: 0, sec: 0)
  end

  def self.pinned_attributes(today)
    { schedule_date: today, ratings_config_version: RatingsConfigVersion.default_version,
      maximum_requests: Integer(ENV.fetch('CBBD_SCHEDULED_MAX_REQUESTS', '50'), 10),
      retries: Integer(ENV.fetch('CBBD_SCHEDULED_RETRIES', '2'), 10) }
  end

  def enqueue_analytics
    with_lock do
      return unless past_status == 'completed' && analytics_status == 'pending'
      return update!(analytics_status: 'stale') unless current_authorization?

      queue_analytics
    end
  end

  def current_authorization?
    schedule_date == Game.current_schedule_date
  end

  def past_dates
    clipped_dates(schedule_date - 3, schedule_date - 1)
  end

  def future_dates
    clipped_dates(schedule_date, schedule_date + 7)
  end

  private

  def pin_season_bounds
    self.season_start_date ||= season&.start_date
    self.season_end_date ||= season&.end_date
  end

  def clipped_dates(first, last)
    ([first, season_start_date].max..[last, season_end_date].min).to_a
  end

  def queue_analytics
    job = CbbdSyncAnalyticsJob.new(id)
    update!(analytics_job_id: job.job_id)
    raise ActiveJob::EnqueueError, 'Analytics enqueue rejected' unless job.enqueue

    update!(analytics_status: 'queued')
  end
end
