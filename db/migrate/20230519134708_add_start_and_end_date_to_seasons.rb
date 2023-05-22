class AddStartAndEndDateToSeasons < ActiveRecord::Migration[7.0]
  def change
    add_column :seasons, :start_date, :date, null: false
    add_column :seasons, :end_date, :date, null: false
  end
end
