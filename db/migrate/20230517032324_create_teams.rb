class CreateTeams < ActiveRecord::Migration[7.0]
  def change
    create_table :teams do |t|
      t.string :school
      t.string :nickname

      t.timestamps
    end
  end
end
