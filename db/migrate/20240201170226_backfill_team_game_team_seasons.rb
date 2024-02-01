class BackfillTeamGameTeamSeasons < ActiveRecord::Migration[7.1]
  def up
    TeamGame.includes(:team, :season).all.each do |g|
      season = TeamSeason.find_by(team_id: g.team_id, season_id: g.season.id)
      g.update!(team_season_id: season.id)
    end

    change_column_null :team_games, :team_season_id, false
  end

  def down
    change_column_null :team_games, :team_season_id, true
  end
end
