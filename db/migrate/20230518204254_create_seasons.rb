class CreateSeasons < ActiveRecord::Migration[7.0]
  def change
    create_table :seasons do |t|
      t.integer :year, index: true, unique: true, null: false
      t.timestamps
    end
  end
end
