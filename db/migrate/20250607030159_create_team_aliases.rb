class CreateTeamAliases < ActiveRecord::Migration[7.1]
  def change
    create_table :team_aliases do |t|
      t.references :team, null: false, foreign_key: true
      t.string :value, null: false
      t.string :source

      t.timestamps
    end

    add_index :team_aliases, [:value, :source], unique: true
  end
end
