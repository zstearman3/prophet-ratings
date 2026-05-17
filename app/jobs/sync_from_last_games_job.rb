# frozen_string_literal: true

class SyncFromLastGamesJob < ApplicationJob
  queue_as :default

  def perform(season_id = nil, enqueue_rankings: true)
    season = resolve_season(season_id)
    return unless season

    (start_date(season)..end_date(season)).each do |date|
      result = Ingestion::GamesIngestionService.new(date:).call
      Rails.logger.debug { "Imported #{result[:imported_rows]} games for #{date}" }
    end

    return unless enqueue_rankings

    UpdateRankingsJob.perform_later(season.id)
  end

  private

  def resolve_season(season_id)
    return Season.find_by(id: season_id) if season_id.present?

    Season.current || Season.last
  end

  def start_date(season)
    latest_start_time = season.games.order(start_time: :desc).pick(:start_time)
    latest_imported_date = latest_start_time && Game.schedule_date_for(latest_start_time)
    [latest_imported_date || season.start_date, season.start_date].max
  end

  def end_date(season)
    [season.end_date, Game.current_schedule_date - 1.day].min
  end
end
