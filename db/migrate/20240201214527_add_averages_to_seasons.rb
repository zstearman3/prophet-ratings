class AddAveragesToSeasons < ActiveRecord::Migration[7.1]
  def change
    add_column :seasons, :average_efficiency, :decimal, precision: 6, scale: 5
    add_column :seasons, :average_pace, :decimal, precision: 6, scale: 5
  end
end
