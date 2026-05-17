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

    scraper = Scraper::GamesScraper.new(date)
    return if scraper.game_count.zero?

    team_data = team_rows(team, scraper.to_json_for_team(team))
    Importer::GamesImporter.import(team_data)

    Rails.logger.debug { "Imported #{team_data.size} games for #{team.school} on #{date}" }
  end

  def team_rows(team, data)
    aliases = team.team_aliases.pluck(:value)
    data.select do |row|
      row[:home_team] == team.school || row[:away_team] == team.school ||
        aliases.include?(row[:home_team]) ||
        aliases.include?(row[:away_team])
    end
  end
end
