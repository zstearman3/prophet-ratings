# frozen_string_literal: true

module Ingestion
  # A name-only side still has an upstream identity; reconciliation must not silently replace it.
  class ObservationParticipantIdentity
    def initialize(resolution, game, label)
      @resolution = resolution
      @game = game
      @label = label
    end

    def validate
      return validate_linked_side if @game.public_send("#{@label}_team_game")

      previous = ::GameObservation.where(game: @game, accepted: true).order(id: :desc).first
      return unless previous

      validate_source_side(previous.normalized_payload.fetch(@label.to_s))
    end

    private

    def validate_linked_side
      conflict unless @resolution.memberships[GameObservation::SIDES.index(@label)]
    end

    def validate_source_side(stored)
      incoming = @resolution.observation.data.fetch(@label)
      external_id = stored['external_team_id']
      consistent = external_id ? external_id == incoming[:external_team_id] : stored['name'] == incoming[:name]
      conflict unless consistent
    end

    def conflict
      raise ObservationResolution::Held.new('conflict', 'participant_or_orientation_conflict')
    end
  end
end
