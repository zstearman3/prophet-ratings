class RemoveTeamSecondaryName < ActiveRecord::Migration[7.1]
  def up
    Team.where.not(secondary_name: [nil, '']).each do |team|
      TeamAlias.create(team: team, value: team.secondary_name, source: 'sports-reference')
    end
    remove_column :teams, :secondary_name
  end

  def down
    add_column :teams, :secondary_name, :string
    TeamAlias.where(source: 'sports-reference').each do |alias_record|
      alias_record.team.update!(secondary_name: alias_record.value)
    end
  end
end
