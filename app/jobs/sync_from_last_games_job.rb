# frozen_string_literal: true

class SyncFromLastGamesJob < ApplicationJob
  queue_as :default

  def perform(season_id = nil, enqueue_rankings: true)
    season = resolve_season(season_id)
    return unless season

    (start_date(season)..end_date(season)).each do |d|
      scraper = Scraper::GamesScraper.new(d)
      @url_position = 0
      @game_count = scraper.game_count

      while @url_position < @game_count
        batch_size = max_url_position - @url_position

        data = scraper.to_json_in_batches(@url_position, batch_size)
        Importer::GamesImporter.import(data)

        Rails.logger.debug { "Imported games #{@url_position} to #{max_url_position} of #{@game_count} for #{d}" }
        @url_position = max_url_position
      end
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
    [latest_start_time || season.start_date, season.start_date].max.to_date
  end

  def end_date(season)
    [season.end_date, Date.yesterday].min
  end

  def max_url_position
    @url_position + 10 < @game_count ? (@url_position + 10) : @game_count
  end
end
