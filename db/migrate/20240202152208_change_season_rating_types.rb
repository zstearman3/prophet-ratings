class ChangeSeasonRatingTypes < ActiveRecord::Migration[7.1]
  def change
    change_column :seasons, :average_efficiency, :decimal, precision: 6, scale: 3
    change_column :seasons, :average_pace, :decimal, precision: 6, scale: 3
  end
end
