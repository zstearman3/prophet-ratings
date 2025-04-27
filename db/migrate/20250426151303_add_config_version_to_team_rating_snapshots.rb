class AddConfigVersionToTeamRatingSnapshots < ActiveRecord::Migration[7.1]
  def change
    add_reference :team_rating_snapshots, :ratings_config_version, foreign_key: true
    remove_column :team_rating_snapshots, :config_bundle_name
  end
end
