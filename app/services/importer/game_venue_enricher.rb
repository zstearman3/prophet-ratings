# frozen_string_literal: true

require 'yaml'

module Importer
  class GameVenueEnricher
    DEFAULT_OVERRIDE_PATH = Rails.root.join('db/data/game_venue_overrides.yml')
    MANUAL_SOURCE = 'manual_override'
    SPORTS_REFERENCE_SOURCE = 'sports_reference_schedule'

    def initialize(games = Game.all, overrides: nil, override_path: DEFAULT_OVERRIDE_PATH, overwrite_manual: false)
      @games = games
      @overrides = overrides
      @override_path = override_path
      @overwrite_manual = overwrite_manual
    end

    def call
      records.each { |game| enrich_game(game) }
    end

    private

    attr_reader :games, :override_path, :overwrite_manual

    def records
      games.respond_to?(:find_each) ? games.find_each : Array(games)
    end

    def enrich_game(game)
      return if manual_classification?(game) && !overwrite_manual

      attrs = manual_override_attributes(game) || inferred_attributes(game)
      game.update!(attrs) if attrs.present?
    end

    def manual_override_attributes(game)
      override = overrides.find { |entry| override_matches_game?(entry, game) }
      return unless override

      venue_type = override.fetch('venue_type')
      {
        venue_type:,
        venue_source: MANUAL_SOURCE,
        venue_confidence: 'manual',
        venue_name: override['venue_name'],
        neutral: venue_type == 'neutral'
      }
    end

    def inferred_attributes(game)
      location = game.location.to_s.strip
      return unknown_attributes(game) if location.blank?

      if home_location?(game, location)
        {
          venue_type: 'home',
          venue_source: SPORTS_REFERENCE_SOURCE,
          venue_confidence: 'confirmed',
          venue_name: location,
          neutral: false
        }
      else
        {
          venue_type: 'neutral',
          venue_source: SPORTS_REFERENCE_SOURCE,
          venue_confidence: 'inferred',
          venue_name: location,
          neutral: true
        }
      end
    end

    def unknown_attributes(game)
      return if game.venue_unknown? && game.venue_confidence == 'unknown' && game.neutral.nil?

      {
        venue_type: 'unknown',
        venue_source: nil,
        venue_confidence: 'unknown',
        venue_name: nil,
        neutral: nil
      }
    end

    def home_location?(game, location)
      home_team = game.home_team
      return false unless home_team

      exact_match?(location, home_team.home_venue) || location_includes?(location, home_team.location)
    end

    def exact_match?(location, expected)
      expected.present? && location.casecmp(expected.strip).zero?
    end

    def location_includes?(location, expected)
      expected.present? && location.downcase.include?(expected.strip.downcase)
    end

    def manual_classification?(game)
      game.venue_source == MANUAL_SOURCE || game.venue_confidence == 'manual'
    end

    def overrides
      @overrides ||= load_overrides
    end

    def load_overrides
      return [] unless override_path.exist?

      YAML.safe_load_file(override_path, permitted_classes: [Date], aliases: false) || []
    end

    def override_matches_game?(entry, game)
      entry['season'].to_i == game.season.year &&
        Date.parse(entry['date'].to_s) == game.start_time.to_date &&
        same_team_pair?(entry['teams'], game)
    rescue ArgumentError
      false
    end

    def same_team_pair?(teams, game)
      Array(teams).map { |team| team.to_s.downcase }.sort == [game.home_team_name, game.away_team_name].map(&:downcase).sort
    end
  end
end
