# frozen_string_literal: true

class GenerateNightlyPredictionsJob < ApplicationJob
  include PinnedModelVersion

  queue_as :default
  around_perform { |_job, block| Season.with_ratings_lock(&block) }

  LOOKAHEAD_DAYS = 7

  def perform(season_id = nil, as_of: Time.current, ratings_config_version_id: nil)
    season = resolve_season(season_id)
    return unless season

    version = RatingsConfigVersion.resolve(ratings_config_version_id)
    season.games.scheduled.where(start_time: as_of..(as_of + LOOKAHEAD_DAYS.days)).find_each do |game|
      game.generate_prediction!(ratings_config_version: version)
    end
  end

  private

  def resolve_season(season_id)
    return Season.find_by(id: season_id) if season_id.present?

    Season.current
  end
end
