# frozen_string_literal: true

class SyncOddsJob < ApplicationJob
  queue_as :default

  def perform
    result = OddsApi::SyncService.call

    Rails.logger.info(
      "Odds API sync complete: fetched=#{result.fetched_count} imported=#{result.imported_count} failed=#{result.failed_count}"
    )

    result.failures.each do |failure|
      Rails.logger.warn("Odds API sync failure: #{failure_message(failure)}")
    end
  end

  private

  def failure_message(failure)
    [
      "odds_api_game_id=#{failure[:odds_api_game_id]}",
      "home_team=#{failure[:home_team]}",
      "away_team=#{failure[:away_team]}",
      "commence_time=#{failure[:commence_time]}",
      "error_class=#{failure[:error_class]}",
      "message=#{failure[:message]}"
    ].join(' ')
  end
end
