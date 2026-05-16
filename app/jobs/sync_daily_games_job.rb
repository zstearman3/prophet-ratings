# frozen_string_literal: true

class SyncDailyGamesJob < ApplicationJob
  queue_as :default

  def perform(date = Date.yesterday)
    result = Ingestion::GamesIngestionService.new(date:).call
    Rails.logger.debug { "Imported #{result[:imported_rows]} games for #{date}" }
  end
end
