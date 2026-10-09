# frozen_string_literal: true

require 'csv'

module Importer
  module Setup
    class BaseDataImporter
      def self.run
        new.run
      end

      def run
        Season.with_ratings_lock do
          ApplicationRecord.transaction do
            import_foundations
          end
        end
      end

      def self.import_team(row)
        Team.find_or_initialize_by(school: row['school']).tap do |team|
          team.assign_attributes(row.to_h.slice('nickname', 'url', 'location', 'slug', 'primary_color',
                                                'short_name', 'home_venue'))
          team.save! if team.changed?
        end
      end

      def self.import_alias(team, value)
        return if value.blank?

        team.team_aliases.find_or_create_by!(value:, source: 'sports-reference')
      rescue ActiveRecord::RecordNotFound
        raise ArgumentError, "Sports Reference alias #{value.inspect} conflicts with another team; review its stored ownership."
      end

      private

      def import_foundations
        import_teams
        import_seasons
        import_team_seasons
        import_conferences
      end

      def import_teams
        CSV.foreach(Rails.root.join('db/seeds/scraped_teams.csv'), headers: true) do |row|
          team = self.class.import_team(row)
          self.class.import_alias(team, row['secondary_name'])
        end
      end

      def import_seasons
        Season.find_or_create_by!(year: 2025) do |season|
          season.assign_attributes(name: '2024-25', start_date: Date.new(2024, 11, 1),
                                   end_date: Date.new(2025, 4, 10), average_efficiency: 105.5,
                                   average_pace: 69.0, current: false)
        end
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
    end
  end
end
