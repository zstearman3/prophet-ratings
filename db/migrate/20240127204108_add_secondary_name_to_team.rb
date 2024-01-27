class AddSecondaryNameToTeam < ActiveRecord::Migration[7.1]
  def change
    add_column :teams, :secondary_name, :string
  end
end
