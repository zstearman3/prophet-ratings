# frozen_string_literal: true

module Ingestion
  # A discarded scheduled entry can be skipped only while its exact reviewed facts and identity decision still hold.
  class ScheduleReviewReplay
    def initialize(observation, resolution, game)
      @observation = observation
      @resolution = resolution
      @game = game
    end

    def call
      return unless reviewed_skip?

      ObservationAudit.new(@observation, @game).retain('reviewed_skip', 'admin_reviewed_schedule_skip')
    end

    private

    def reviewed_skip?
      data = @observation.data
      return false unless data.values_at(:provider, :source_status, :source_completed) == ['cbbd', 'scheduled', false]

      review = GameScheduleReview.find_by(ignored_external_id: data[:external_game_id])
      review&.current?(@game, @resolution) && review.ignored_fingerprint == GameScheduleReview.payload_fingerprint(data)
    end
  end
end
