namespace :db do
  desc 'Update slugs for all teams'
  task update_team_slugs: :environment do
    Team.find_each do |team|
      team.slug = team.school.parameterize
      team.save!
    end
    puts "Updated slugs for #{Team.count} teams"
  end
end
