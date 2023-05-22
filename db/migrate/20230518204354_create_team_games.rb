class CreateTeamGames < ActiveRecord::Migration[7.0]
  def change
    create_table :team_games do |t|
      t.references :team, null: false
      t.references :game, null: false
      t.timestamps
    end
  end
end
