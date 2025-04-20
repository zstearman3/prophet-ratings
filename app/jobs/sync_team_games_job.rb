class SyncTeamGamesJob < ApplicationJob
  queue_as :default

  def perform(team_id, season_id = Season.last.id)
    team = Team.find(team_id)
    season = Season.find(season_id)
    end_date = [season.end_date, Date.yesterday].min

    (season.start_date..end_date).each do |date|
      Rails.logger.debug("Looking for matches on #{date}")

      scraper = Scraper::GamesScraper.new(date)
      game_count = scraper.game_count

      next if game_count == 0
      
      data = scraper.to_json_for_team(team)

      # Keep only games where this team is involved
      team_data = data.select do |row|
        row[:home_team] == team.school || row[:away_team] == team.school ||
        row[:home_team] == team.secondary_name || row[:away_team] == team.secondary_name
      end

      Importer::GamesImporter.import(team_data)

      Rails.logger.debug("Imported #{team_data.size} games for #{team.school} on #{date}")
    end
  end
end
