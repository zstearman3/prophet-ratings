# frozen_string_literal: true

module Ingestion
  # Explicit admin selection authorizes one exact stored source under all writer locks.
  class GameIssueResolution
    def initialize(issue:, user:, action:, values:, fingerprint:)
      @issue = issue
      @submission = { user:, action:, values: values.to_h.stringify_keys.transform_values(&:to_s), fingerprint: }
    end

    def call
      validate_admin
      resolve_with_locks
    rescue ObservationResolution::Held, GameObservation::Invalid => error
      raise ArgumentError, error.message
    end

    private

    def resolve_with_locks
      GamesIngestionService.with_date_lock(@issue.schedule_date) do
        Season.with_ratings_lock { Game.transaction(requires_new: true) { resolve } }
      end
    end

    def validate_admin
      raise ArgumentError, 'Admin approval required.' unless @submission[:user]&.admin?
    end

    def resolve
      lock_evidence
      repeated_decision || apply_decision
    end

    def apply_decision
      validate_submission
      applied = @submission[:action] == 'acknowledge' || apply_result
      create_decision.tap { @issue.update!(state: applied ? 'resolved' : 'open') }
    end

    def lock_evidence
      @issue.lock!
      @issue.game&.lock!
    end

    def repeated_decision
      previous = @issue.decisions.find_by(source_fingerprint: @issue.source_fingerprint,
                                          comparison_fingerprint: @submission[:fingerprint], action: @submission[:action],
                                          values: @submission[:values])
      return previous if previous && pending_comparison?

      candidate = @issue.game
      previous if previous && candidate && ScoringException.new(@issue).matches_game?(candidate)
    end

    def pending_comparison?
      @issue.state == 'open' && @issue.comparison_fingerprint == @submission[:fingerprint]
    end

    def validate_submission
      unless @issue.comparison_fingerprint == @submission[:fingerprint]
        raise ArgumentError, 'Source or game changed; reload before applying.'
      end

      allowed = { 'scoring' => %w[acknowledge select_scores], 'participants' => ['select_participants'],
                  'source_revision' => ['accept_source'] }
      raise ArgumentError, 'This issue requires a source retry or identity review.' unless allowed_action?(allowed)

      validate_acknowledgment if @submission[:action] == 'acknowledge'
    end

    def allowed_action?(actions)
      actions.fetch(@issue.category, []).include?(@submission[:action])
    end

    def validate_acknowledgment
      candidate = @issue.game
      return if candidate && @issue.applied_source_current? && ScoringException.new(@issue).matches_game?(candidate)

      raise ArgumentError, 'The imported result changed; reload its evidence.'
    end

    def apply_result
      GameIssueResultWriter.new(issue: @issue, action: @submission[:action], values: @submission[:values]).call
    end

    def create_decision
      @issue.decisions.create!(actor: @submission[:user], action: @submission[:action], values: @submission[:values],
                               source_fingerprint: @issue.source_fingerprint, comparison_fingerprint: @submission[:fingerprint])
    end
  end
end
