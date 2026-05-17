# frozen_string_literal: true

class SyncDailyGamesJob < ApplicationJob
  queue_as :default

  def perform(date = Game.current_schedule_date - 1.day)
    result = Ingestion::GamesIngestionService.new(date:).call
    Rails.logger.info { "Imported #{result[:imported_rows]} games for #{date}" }
  end
end
