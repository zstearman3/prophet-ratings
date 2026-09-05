# frozen_string_literal: true

class UpdateRankingsJob < ApplicationJob
  ADVISORY_LOCK_KEY = 'prophet-ratings:update-rankings'

  queue_as :default
  around_perform :run_with_exclusive_lock

  def perform(season = Season.current, enqueue_nightly_predictions: true)
    season = resolve_season(season)
    return unless season

    ProphetRatings::OverallRatingsCalculator.new(season).call
    return unless enqueue_nightly_predictions

    GenerateNightlyPredictionsJob.perform_later(season.id)
  end

  private

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
