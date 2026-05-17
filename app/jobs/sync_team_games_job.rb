# frozen_string_literal: true

class SyncTeamGamesJob < ApplicationJob
  queue_as :default

  def perform(team_id, season_id = Season.last.id)
    team = Team.find(team_id)
    season = Season.find(season_id)

    (season.start_date..sync_end_date(season)).each do |date|
      import_team_games_for_date(team, date)
    end
  end

  private

  def sync_end_date(season)
    [season.end_date, Game.current_schedule_date - 1.day].min
  end

  def import_team_games_for_date(team, date)
    Rails.logger.debug { "Looking for matches on #{date}" }

    result = Ingestion::GamesIngestionService.new(date:, team:).call

    Rails.logger.debug { "Imported #{result[:imported_rows]} games for #{team.school} on #{date}" }
  end
end
