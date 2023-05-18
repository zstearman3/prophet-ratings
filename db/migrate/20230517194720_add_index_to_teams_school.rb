class AddIndexToTeamsSchool < ActiveRecord::Migration[7.0]
  def change
    add_index :teams, :school, unique: true
    
    add_column :teams, :url, :string
    add_column :teams, :location, :string
  end
end
