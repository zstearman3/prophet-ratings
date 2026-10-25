# frozen_string_literal: true

class UpdateRankingsJob < HeavyJob
  ADVISORY_LOCK_KEY = Season::RATINGS_LOCK_KEY

  include PinnedModelVersion

  around_perform :run_with_exclusive_lock

  def perform(season = Season.current, enqueue_nightly_predictions: true, **options)
    season = resolve_season(season)

    version = self.class.recalculate(season, options[:ratings_config_version_id], sync_schedule_date: options[:sync_schedule_date])
    return unless version && enqueue_nightly_predictions

    ActiveRecord.after_all_transactions_commit do
      GenerateNightlyPredictionsJob.perform_later(season.id, ratings_config_version_id: version.id)
    end
  end

  private

  public_class_method def self.recalculate(season, version_id, sync_schedule_date: nil)
    execution_date = Game.current_schedule_date
    return unless sync_date_current?(execution_date, sync_schedule_date)

    version = RatingsConfigVersion.resolve(version_id)
    ProphetRatings::OverallRatingsCalculator.new(season, ratings_config_version: version).call(as_of: execution_date - 1.day)
    version
  end

  private_class_method def self.sync_date_current?(execution_date, sync_schedule_date)
    return true if [nil, execution_date.iso8601].include?(sync_schedule_date&.to_s)

    Rails.logger.info("Skipping UpdateRankingsJob: partial sync authorization for #{sync_schedule_date} " \
                      "does not cover execution date #{execution_date}")
    false
  end

  def run_with_exclusive_lock
    acquired = GoodJob::Job.advisory_lock_key(ADVISORY_LOCK_KEY) do
      yield
      true
    end
    logger.info { 'Skipping UpdateRankingsJob: another instance is already running' } unless acquired
  end

  def resolve_season(season)
    return Season.find(season) if season.is_a?(Integer)

    season
  end
end
