# frozen_string_literal: true

module Ingestion
  # Only raw canonical values are written here. The existing finalizer owns all derived mathematics.
  class ObservationWriter
    attr_reader :observation, :resolution, :game

    def initialize(observation, resolution, game)
      @observation = observation
      @resolution = resolution
      @game = game
    end

    def attributes
      sides = self.class.side_attributes(data)
      sides = sides.except(:home_team_score, :away_team_score) if observation.schedule_projection?
      { season_id: resolution.season.id, start_time:, url: source_url }.merge(sides).merge(venue_attributes)
    end

    def changes
      attributes.stringify_keys.reject { |key, value| game.attributes[key] == value }
    end

    def identical?
      return false unless game.persisted? && changes.empty?
      return false if observation.final? && !game.final?

      GameObservation::SIDES.all? { |label| identical_side?(label) }
    end

    def call
      game.update!(attributes)
      GameObservation::SIDES.each_with_index { |label, index| write_side(label, index) }
      finalize if observation.strict_final?
      game
    end

    def self.side_attributes(data)
      home, away = data.values_at(:home, :away)
      { home_team_name: home[:name], home_team_score: home[:score], away_team_name: away[:name], away_team_score: away[:score] }
    end

    private

    def data = observation.data

    def finalize
      GameObservation::SIDES.each { |label| game.association(:"#{label}_team_game").reset }
      game.finalize
    end

    def identical_side?(label)
      side = game.public_send("#{label}_team_game")
      side && raw_stats(label).all? { |key, value| side.public_send(key) == value }
    end

    def raw_stats(label)
      observation.strict_final? ? data[label][:stats] : {}
    end

    def start_time
      start, date = data.values_at(:start_time, :schedule_date)
      return Time.iso8601(start).in_time_zone if start
      return game.start_time if game.persisted? && game.schedule_date.iso8601 == date

      Game.schedule_time_for(Date.iso8601(date))
    end

    def source_url
      stored = game.url
      return stored if game.persisted? && (observation.schedule_projection? || other_provider_provenance?)

      data[:source_url].presence || stored || data[:external_game_id]
    end

    def other_provider_provenance?
      ::GameObservation.where(game:, accepted: true).where.not(provider: data[:provider]).exists?
    end

    def venue_attributes
      return {} if game.venue_confidence == 'manual' || game.venue_source == 'manual_override'

      incoming = data.fetch(:venue, {})
      return {} if incoming[:venue_source] == 'sports_reference_box_score_header' && stored_venue?

      incoming.slice(:venue_type, :venue_source, :venue_confidence, :venue_name, :neutral)
    end

    def stored_venue?
      !game.venue_unknown? || game.venue_source.present? || game.venue_name.present? || [true, false].include?(game.neutral)
    end

    def write_side(label, index)
      membership, opponent = resolution.memberships.values_at(index, 1 - index)
      side = TeamGame.find_or_initialize_by(game:, home: label == :home)
      attrs = { team: membership.team, team_season: membership, opponent_team_season: opponent }
      side.update!(attrs.merge(raw_stats(label)))
    end
  end
end
