# frozen_string_literal: true

module Ingestion
  # One explicit admin decision and its canonical import commit together under existing date/source locks.
  class ScoringReviewImport
    def initialize(run:, observation:, user:, choices:, confirmed:)
      @run = run
      @source = observation
      @submission = { user:, choices: choices.to_h.stringify_keys.transform_values(&:to_s), confirmed: }
    end

    def call
      validate_submission
      import_with_locks
    rescue ObservationResolution::Held => error
      raise ArgumentError, error.message
    end

    def self.validate_candidate(resolution)
      candidate = resolution.game
      return unless candidate

      candidate.lock!
      resolution.validate_game(candidate)
      raise ArgumentError, 'A completed game already exists; this review cannot overwrite it.' if candidate.completed?
    end

    private

    attr_reader :run, :source, :submission

    def choices = submission.fetch(:choices)

    def source_fingerprint = GameScoringReview.source_fingerprint(source.normalized_payload)

    def validate_submission
      raise ArgumentError, 'Admin approval required.' unless submission.fetch(:user).admin?
      raise ArgumentError, 'Explicitly confirm the selected result.' unless submission[:confirmed] == '1'

      allowed = run.historical? && run.cbbd? && ScheduleRefreshRun::TERMINAL.include?(run.status)
      raise ArgumentError, 'Observation is outside this historical CBBD run.' unless allowed && run.rejection_observations.key?(source.id)
    end

    def import_with_locks
      GamesIngestionService.with_date_lock(Date.iso8601(source.normalized_payload.fetch('schedule_date'))) do
        Game.transaction(requires_new: true) { import_review }
      end
    end

    def import_review
      context = review_context
      validate_latest_source
      previous = GameScoringReview.find_by(source_fingerprint:)
      previous ? repeat_review(previous, context.fetch(:resolution)) : apply_review(context)
    end

    def review_context
      season = run.season
      observation = GameObservation.new(ScoringReviewEvidence.new(source, season).validate.selected_payload(choices)).validate
      resolution = ObservationResolution.new(observation, season).resolve
      resolution.lock
      { observation:, resolution: }
    end

    def apply_review(context)
      self.class.validate_candidate(context.fetch(:resolution))
      review = create_review(context)
      result = GameObservationImporter.new(**context.slice(:observation), season: run.season, scoring_review: review).call
      validate_result(result)
      review.reload
    end

    def validate_result(result)
      return unless GameSyncProvider.held?(result)

      raise ArgumentError, 'Reviewed import could not be applied; refresh the evidence and identity review.'
    end

    def validate_latest_source
      latest = ::GameObservation.where(provider: source.provider, external_game_id: source.external_game_id, scoring_review_id: nil)
                                .where('id > ?', source.id).order(id: :desc).first
      return unless latest
      return if GameScoringReview.source_fingerprint(latest.normalized_payload) == source_fingerprint

      raise ArgumentError, 'Source facts changed; open fresh rejection evidence before reviewing.'
    end

    def repeat_review(review, resolution)
      validate_saved_choices(review)
      review.validate_current(resolution)
      review
    end

    def validate_saved_choices(review)
      return if review.choices == choices

      raise ArgumentError, 'This source was already reviewed with different choices.'
    end

    def create_review(context)
      GameScoringReview.create!(season: run.season, schedule_refresh_run: run, source_observation: source,
                                reviewed_by: submission.fetch(:user), source_fingerprint:, choices:,
                                approved_payload: context.fetch(:observation).data.as_json,
                                participants: GameScoringReview.participants_for(context.fetch(:resolution)))
    end
  end
end
