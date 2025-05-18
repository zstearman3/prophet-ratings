#frozen_string_literal: true

require 'csv'

teams_file = File.join(Rails.root, 'db', 'seeds', 'scraped_teams.csv')

CSV.foreach(teams_file, headers: true) do |row|
  Team.upsert({
    school: row["school"],
    nickname: row["nickname"],
    url: row["url"],
    location: row["location"],
    secondary_name: row["secondary_name"]},
    unique_by: :school
  )
end

Season.find_or_create_by(
  year: 2024, 
  start_date: Date.new(2023, 11, 6),
  end_date: Date.new(2024, 4, 8),
)

Team.all.each do |team|
  Season.all.each { |s| TeamSeason.find_or_create_by(team: team, season: s)}
end

### Seed Conferences ###
conferences_file = File.join(Rails.root, 'db', 'seeds', 'conferences.csv')

CSV.foreach(conferences_file, headers: true) do |row|
  Conference.find_or_create_by!(
    name: row["name"],
    abbreviation: row["abbreviation"],
    slug: row["slug"]
  )
end

team_conf_file = File.join(Rails.root, 'db', 'seeds', 'team_conferences.csv')

CSV.foreach(team_conf_file, headers: true) do |row|
  team = Team.find_by!(school: row["school"])
  conf = Conference.find_by!(slug: row["conference_slug"])
  start_season = Season.find_by!(year: row["start_year"].to_i)
  end_season = row["end_year"].present? ? Season.find_by!(year: row["end_year"].to_i) : nil

  TeamConference.find_or_create_by!(
    team: team,
    conference: conf,
    start_season: start_season,
    end_season: end_season
  )
end