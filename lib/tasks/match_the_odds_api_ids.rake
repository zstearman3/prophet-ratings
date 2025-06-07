namespace :teams do
  desc 'Match and update the_odds_api_team_id from external mapping'
  task match_the_odds_api_ids: :environment do
    require 'json'
    require_relative '../../app/services/team_matcher'

    json_path = Rails.root.join('db', 'data', 'the-odds-api-team-map.json')
    data = JSON.parse(File.read(json_path))
    matcher = TeamMatcher.new

    matched = 0
    not_found = []

    data.each do |entry|
      name = entry['full_name']
      odds_api_id = entry['id']
      team = matcher.match(name)

      if team
        team.update!(the_odds_api_team_id: odds_api_id)
        puts "Matched: #{name} => #{team.school} (#{odds_api_id})"
        matched += 1
      else
        puts "No match for: #{name} (#{odds_api_id})"
        not_found << name
      end
    end

    puts "\nMatched #{matched} teams."
    puts "No match for #{not_found.size} teams:" if not_found.any?
    not_found.each { |n| puts "  - #{n}" }
  end
end
