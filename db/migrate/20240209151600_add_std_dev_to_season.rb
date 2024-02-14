class AddStdDevToSeason < ActiveRecord::Migration[7.1]
  def change
    add_column :seasons, :efficiency_std_deviation, :decimal, precision: 6, scale: 3
    add_column :seasons, :pace_std_deviation, :decimal, precision: 6, scale: 3
  end
end
