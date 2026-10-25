# frozen_string_literal: true

module Ingestion
  # Reuse decisions for unchanged source facts before ordinary scoring rejection, never for changed inputs.
  class ScoringReviewReplay
    def initialize(row, season)
      @row = row
      @season = season
      @source = Cbbd::ImportObservation.new(row, season).payload
    end

    def call
      replay_if_reviewed
    rescue ObservationResolution::Held => error
      retain_hold(error.outcome, error.message)
    rescue ArgumentError, GameObservation::Invalid
      retain_hold('conflict', 'reviewed_source_changed')
    end

    private

    def replay_if_reviewed
      review = find_review
      Game.transaction(requires_new: true) { replay(review) } if review
    end

    def find_review
      GameScoringReview.joins(:source_observation).where(season: @season)
                       .where(game_observations: { provider: @source[:provider], external_game_id: @source[:external_game_id] }).first
    end

    def retain_hold(outcome, reason)
      ObservationAudit.new(GameObservation.new(@source), nil).retain(outcome, reason)
    end

    def replay(review)
      observation = validated_observation(review)
      resolution = ObservationResolution.new(observation, @season).resolve
      resolution.lock
      review.validate_current(resolution)
      GameObservationImporter.new(observation:, season: @season, scoring_review: review).call
    end

    def validated_observation(review)
      evidence = ScoringReviewEvidence.new(@row, @season).validate
      unless GameScoringReview.source_fingerprint(evidence.payload) == review.source_fingerprint
        raise ObservationResolution::Held.new('conflict', 'reviewed_source_changed')
      end

      payload = review.approved_payload.merge('raw_payload' => @row, 'captured_at' => @source[:captured_at],
                                              'payload_digest' => @source[:payload_digest])
      GameObservation.new(payload).validate
    end
  end
end
