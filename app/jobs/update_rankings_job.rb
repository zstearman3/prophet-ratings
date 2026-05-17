# frozen_string_literal: true

class UpdateRankingsJob < ApplicationJob
  queue_as :default

  def perform(season = Season.current, enqueue_nightly_predictions: true)
    season = resolve_season(season)
    return unless season

    ProphetRatings::OverallRatingsCalculator.new(season).call
    return unless enqueue_nightly_predictions

    GenerateNightlyPredictionsJob.perform_later(season.id)
  end

  private

  def resolve_season(season)
    return Season.find_by(id: season) if season.is_a?(Integer)

    season
  end
end
