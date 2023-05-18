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
