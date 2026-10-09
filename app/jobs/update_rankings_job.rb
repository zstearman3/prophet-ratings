# frozen_string_literal: true

class UpdateRankingsJob < ApplicationJob
  ADVISORY_LOCK_KEY = Season::RATINGS_LOCK_KEY

  include PinnedModelVersion

  queue_as :default
  around_perform :run_with_exclusive_lock

  def perform(season = Season.current, enqueue_nightly_predictions: true, ratings_config_version_id: nil)
    season = resolve_season(season)
    return unless season

    version = self.class.recalculate(season, ratings_config_version_id)
    return unless enqueue_nightly_predictions

    GenerateNightlyPredictionsJob.perform_later(season.id, ratings_config_version_id: version.id)
  end

  private

  public_class_method def self.recalculate(season, version_id)
    version = RatingsConfigVersion.resolve(version_id)
    ProphetRatings::OverallRatingsCalculator.new(season, ratings_config_version: version).call
    version
  end

  def run_with_exclusive_lock
    acquired = GoodJob::Job.advisory_lock_key(ADVISORY_LOCK_KEY) do
      yield
      true
    end
    logger.info { 'Skipping UpdateRankingsJob: another instance is already running' } unless acquired
  end

  def resolve_season(season)
    return Season.find_by(id: season) if season.is_a?(Integer)

    season
  end
end
