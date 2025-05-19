class AddCurrentAndDisplayNameToSeasons < ActiveRecord::Migration[7.1]
  def change
    add_column :seasons, :current, :boolean, default: false
    add_column :seasons, :name, :string

    add_index :seasons, :current, unique: true, where: "current IS TRUE"
  end
end
