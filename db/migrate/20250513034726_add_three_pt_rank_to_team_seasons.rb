class AddThreePtRankToTeamSeasons < ActiveRecord::Migration[7.1]
  def change
    add_column :team_seasons, :adj_three_pt_attempt_rate_rank, :integer
    add_column :team_seasons, :adj_three_pt_attempt_rate_allowed_rank, :integer
    add_column :team_seasons, :adj_pace_rank, :integer
  end
end
