# frozen_string_literal: true

module Ingestion
  # An explicit pending schedule choice and its source retirement commit together.
  class ScheduleReviewResolution
    def initialize(run:, observation:, user:, choice:, fingerprint:)
      @run = run
      @source = observation
      @submission = { user:, choice:, fingerprint: }
    end

    def call
      validate_submission
      resolve_submission
    rescue ObservationResolution::Held, GameObservation::Invalid, GameExternalIdentity::Conflict => error
      raise ArgumentError, error.message
    end

    def self.with_date_locks(dates, &)
      return yield if dates.empty?

      GamesIngestionService.with_date_lock(dates.first) { with_date_locks(dates.drop(1), &) }
    end

    private

    attr_reader :run, :source, :submission, :evidence

    def validate_submission
      raise ArgumentError, 'Admin approval required.' unless submission.fetch(:user).admin?
      raise ArgumentError, 'Choose which schedule entry to keep.' unless %w[existing incoming].include?(submission[:choice])
      raise ArgumentError, 'Refresh the comparison before approving.' if submission[:fingerprint].blank?

      allowed = !run.historical? && run.cbbd? && ScheduleRefreshRun::TERMINAL.include?(run.status) &&
                run.rejection_observations.key?(source.id)
      raise ArgumentError, 'Observation is outside this completed upcoming CBBD run.' unless allowed
    end

    def resolve_submission
      previous = GameScheduleReview.find_by(source_observation: source)
      previous ? repeat(previous) : resolve_new
    end

    def resolve_new
      @evidence = ScheduleReviewEvidence.new(source, run.season).validate
      self.class.with_date_locks(evidence.dates) do
        Game.transaction(requires_new: true) { apply_locked }
      end
    end

    def apply_locked
      lock_candidate
      previous = GameScheduleReview.find_by(source_observation: source)
      previous ? repeat(previous) : apply_selection
    end

    def apply_selection
      validate_comparison
      retire_source
      create_review
    end

    def lock_candidate
      evidence.resolution.lock
      evidence.game.lock!
    end

    def validate_comparison
      locked_game_id = evidence.game.id
      current = ScheduleReviewEvidence.new(source, run.season).validate
      @evidence = current
      return if current.game.id == locked_game_id && current.fingerprint == submission[:fingerprint]

      raise ArgumentError, 'Schedule evidence changed; reload the comparison before approving.'
    end

    def retire_source
      game = evidence.game
      incoming_key = evidence.incoming.data.fetch(:external_game_id)
      if submission[:choice] == 'incoming'
        GameExternalIdentity.active.find_by!(game:, provider: 'cbbd').supersede!(external_id: incoming_key)
        write_incoming
      else
        GameExternalIdentity.create!(game:, provider: 'cbbd', external_id: incoming_key, superseded_at: Time.current)
      end
    end

    def write_incoming
      writer = ObservationWriter.new(evidence.incoming, evidence.resolution, evidence.game)
      changes = writer.changes
      ObservationAudit.new(writer.observation, writer.call).retain('scheduled', 'admin_reviewed_schedule', accepted: true, changes:)
    end

    def create_review
      selected, ignored = selected_payloads
      GameScheduleReview.create!(**review_attributes, selected_payload: selected,
                                                      selected_schedule: evidence.schedule_for(submission[:choice]),
                                                      selected_external_id: selected.fetch('external_game_id'),
                                                      ignored_external_id: ignored.fetch('external_game_id'),
                                                      ignored_fingerprint: GameScheduleReview.payload_fingerprint(ignored))
    end

    def review_attributes
      { season: run.season, schedule_refresh_run: run, game: evidence.game, source_observation: source,
        prior_observation: evidence.prior, reviewed_by: submission[:user], choice: submission[:choice],
        comparison_fingerprint: submission[:fingerprint], participants: GameScheduleReview.participants_for(evidence.resolution) }
    end

    def selected_payloads
      payloads = [evidence.prior.normalized_payload, evidence.incoming.data.as_json]
      submission[:choice] == 'incoming' ? payloads.reverse : payloads
    end

    def repeat(review)
      valid = review.choice == submission[:choice] && review.comparison_fingerprint == submission[:fingerprint]
      raise ArgumentError, 'This source was already reviewed with a different selection or comparison.' unless valid

      review
    end
  end
end
