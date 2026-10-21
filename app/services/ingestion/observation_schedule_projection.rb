# frozen_string_literal: true

module Ingestion
  # Missing source IDs permit pending metadata only, without accepting result provenance.
  class ObservationScheduleProjection
    def initialize(observation, resolution, game)
      @observation = observation
      @game = game
      @writer = ObservationWriter.new(observation, resolution, game)
    end

    def call
      raise ObservationResolution::Held.new('unmatched', 'schedule_projection_requires_pending_game') unless game.scheduled?
      raise ObservationResolution::Held.new('unmatched', 'missing_schedule_document_url') if writer.attributes[:url].blank?

      ObservationFreshness.new(observation, game).validate_projection(identical: writer.identical?)
      persist
    end

    private

    attr_reader :observation, :game, :writer

    def persist
      identical = writer.identical?
      changes = writer.changes
      writer.call unless identical
      ObservationAudit.new(observation, game).retain(identical ? 'unchanged' : 'projected',
                                                     ObservationAudit::PROJECTION_REASON, changes:)
    end
  end
end
