class BackfillTeamAliases < ActiveRecord::Migration[7.1]
  def up
    Team.find_each do |team|
      secondary_name = team.team_aliases.find_by(source: 'sports-reference')&.value

      TeamAlias.upsert({team_id: team.id, value: "#{team.school} #{team.nickname}", source: 'backfill'}, unique_by: [:value, :source])
      if team.short_name.present?
        TeamAlias.upsert({team_id: team.id, value: team.short_name, source: 'backfill'}, unique_by: [:value, :source])
        TeamAlias.upsert({team_id: team.id, value: "#{team.short_name} #{team.nickname}", source: 'backfill'}, unique_by: [:value, :source])
      end
      if secondary_name.present?
        TeamAlias.upsert({team_id: team.id, value: "#{secondary_name} #{team.nickname}", source: 'backfill'}, unique_by: [:value, :source])
      end
    end
  end

  def down
    TeamAlias.where(source: 'backfill').destroy_all
  end
end
