# frozen_string_literal: true

module Ingestion
  # Apply reported points immediately, preserving exact source evidence and a narrow arithmetic exception.
  class ScoringDiscrepancyImport
    def initialize(row:, season:)
      @row = row
      @season = season
      @context = {}
    end

    def call
      Game.transaction(requires_new: true) { import }
    end

    private

    def import
      prepare_evidence
      prepare_exception
      finish(import_payload)
    rescue ObservationResolution::Held => error
      ObservationAudit.new(GameObservation.new(@context.fetch(:source)), nil).retain(error.outcome, error.message)
    end

    def import_payload
      GameObservationImporter.new(observation: @context.fetch(:payload), season: @season,
                                  scoring_exception: ScoringException.new(issue)).call
    end

    def issue
      @context.fetch(:issue)
    end

    def prepare_evidence
      evidence = ScoringReviewEvidence.new(@row, @season).validate
      @context[:source] = evidence.payload
      @context[:payload] = evidence.selected_payload(reported_choices(evidence))
    end

    def reported_choices(evidence)
      affected = evidence.candidates.select { |_label, totals| totals.size > 1 }.keys
      affected.index_with { |label| @context[:source].fetch(label.to_sym).fetch(:score) }
    end

    def prepare_exception
      source = ObservationAudit.new(GameObservation.new(@context.fetch(:source)), nil)
                               .retain('invalid', @row.fetch('reasons').join('; '))
      issue = GameIngestionIssue.capture!(season: @season, observation: ::GameObservation.find(source[:observation_id]),
                                          category: 'scoring')
      @context[:issue] = issue
      @context[:previous] = issue.attributes.slice('effective_payload', 'participants')
      save_effective_payload
    end

    def save_effective_payload
      payload = @context.fetch(:payload)
      resolution = ObservationResolution.new(GameObservation.new(payload).validate, @season).resolve
      @context.fetch(:issue).update!(effective_payload: payload.except(:raw_payload).as_json,
                                     participants: GameScoringReview.participants_for(resolution))
    end

    def restore_previous
      issue.update!(@context.fetch(:previous))
    end

    def associate_game(game_id)
      issue.update!(game_id:) if game_id
    end

    def finish(report)
      restore_previous unless report[:applied]
      associate_game(report[:game_id])
      report.merge(issue_ids: [issue.id])
    end
  end
end
