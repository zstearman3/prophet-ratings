class AddHomeVenueToTeams < ActiveRecord::Migration[7.1]
  def change
    add_column :teams, :home_venue, :string
  end
end
