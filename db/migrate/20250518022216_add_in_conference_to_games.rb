class AddInConferenceToGames < ActiveRecord::Migration[7.1]
  def change
    add_column :games, :in_conference, :boolean, default: false
    add_column :team_seasons, :conference_wins, :integer, default: 0
    add_column :team_seasons, :conference_losses, :integer, default: 0
  end
end
