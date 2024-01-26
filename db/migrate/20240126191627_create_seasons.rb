class CreateSeasons < ActiveRecord::Migration[7.1]
  def change
    create_table :seasons do |t|
      t.integer "year", null: false
      t.date "start_date", null: false
      t.date "end_date", null: false
      t.index ["year"], name: "index_seasons_on_year", unique: true

      t.timestamps
    end
  end
end
