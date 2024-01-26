require 'csv'

teams_file = File.join(Rails.root, 'db', 'seeds', 'scraped_teams.csv')

CSV.foreach(teams_file, headers: true) do |row|
  Team.upsert({
    school: row["school"],
    nickname: row["nickname"],
    url: row["url"],
    location: row["location"]},
    unique_by: :school
  )
end

Season.find_or_create_by(
  year: 2024, 
  start_date: Date.new(2023, 11, 07),
  end_date: Date.new(2024, 04, 03)
)

Team.all.each do |team|
  Season.all.each { |s| TeamSeason.find_or_create_by(team: team, season: s)}
end
