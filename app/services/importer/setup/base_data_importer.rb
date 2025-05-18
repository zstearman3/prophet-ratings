# frozen_string_literal: true

require 'csv'

module Importer
  class BaseDataImporter
    def self.run
      new.run
    end

    def run
      import_teams
      import_seasons
      import_team_seasons
      import_conferences
      import_team_conferences
    end

    private

    def import_teams
      path = Rails.root.join('db/seeds/scraped_teams.csv')
      CSV.foreach(path, headers: true) do |row|
        Team.upsert({
                      school: row['school'],
                      nickname: row['nickname'],
                      url: row['url'],
                      location: row['location'],
                      secondary_name: row['secondary_name']
                    }, unique_by: :school)
      end
    end

    def import_seasons
      Season.find_or_create_by!(
        year: 2024,
        start_date: Date.new(2023, 11, 6),
        end_date: Date.new(2024, 4, 8)
      )
    end

    def import_team_seasons
      Team.find_each do |team|
        Season.find_each { |season| TeamSeason.find_or_create_by!(team:, season:) }
      end
    end

    def import_conferences
      path = Rails.root.join('db/seeds/conferences.csv')
      CSV.foreach(path, headers: true) do |row|
        Conference.find_or_create_by!(
          name: row['name'],
          abbreviation: row['abbreviation'],
          slug: row['slug']
        )
      end
    end

    def import_team_conferences
      path = Rails.root.join('db/seeds/team_conferences.csv')
      CSV.foreach(path, headers: true) do |row|
        team = Team.find_by!(school: row['school'])
        conf = Conference.find_by!(slug: row['conference_slug'])
        start_season = Season.find_by!(year: row['start_year'].to_i)
        end_season = row['end_year'].present? ? Season.find_by!(year: row['end_year'].to_i) : nil

        TeamConference.find_or_create_by!(
          team:,
          conference: conf,
          start_season:,
          end_season:
        )
      end
    end
  end
end
