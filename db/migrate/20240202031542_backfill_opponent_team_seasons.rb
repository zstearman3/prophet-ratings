class BackfillOpponentTeamSeasons < ActiveRecord::Migration[7.1]
  def up
    TeamGame.all.each do |team_game|
      opponent_game = TeamGame.where(game: team_game.game).where.not(id: team_game.id).first

      team_game.update!(opponent_team_season_id: opponent_game&.team_season_id)
    end
  end

  def down; end
end
