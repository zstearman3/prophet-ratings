class AddFieldsToTeams < ActiveRecord::Migration[7.1]
  def change
    add_column :teams, :primary_color, :string
    add_column :teams, :short_name, :string
  end
end
