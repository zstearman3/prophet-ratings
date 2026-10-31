# frozen_string_literal: true

class GenerateNightlyPredictionsJob < HeavyJob
  include PinnedModelVersion

  around_perform { |_job, block| Season.with_ratings_lock(&block) }

  LOOKAHEAD_DAYS = 7

  def perform(season_id = nil, as_of: Time.current, ratings_config_version_id: nil)
    season = resolve_season(season_id)
    return unless season

    self.class.generate_predictions(season, as_of:, ratings_config_version_id:)
    ActiveRecord.after_all_transactions_commit { GenerateBetRecommendationsJob.perform_later }
  end

  private

  public_class_method def self.generate_predictions(season, as_of:, ratings_config_version_id:)
    version = RatingsConfigVersion.resolve(ratings_config_version_id)
    season.games.scheduled.where(start_time: as_of..(as_of + LOOKAHEAD_DAYS.days)).find_each do |game|
      game.generate_prediction!(ratings_config_version: version)
    end
  end

  # Lock waits defer this independent pass; actual errors retain ApplicationJob's retry budget.
  def retry_heavy
    retry_job(wait: 1.minute, queue: :heavy)
  end

  def resolve_season(season_id)
    return Season.find_by(id: season_id) if season_id.present?

    Season.current
  end
end
