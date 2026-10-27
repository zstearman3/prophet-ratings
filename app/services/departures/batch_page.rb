# frozen_string_literal: true

module Departures
  # GETs consume retained projections only; old data requires an explicit background validation.
  class BatchPage
    EMPTY_REPORT = { 'selections' => [], 'teams' => [], 'gaps' => [], 'failures' => [] }.freeze
    LABELS = { 'queued' => 'Validation queued', 'running' => 'Validation in progress', 'failed' => 'Validation failed',
               'stale' => 'Validation stale', 'publish_failed' => 'Publication failed', 'published' => 'Published inputs' }.freeze

    def initialize(batch, attributes = {})
      @batch = batch
      @attributes = attributes
    end

    def call
      history = history_rows
      { attempt:, history: history.first(10), operation:, report:, players: operation&.choices&.fetch('players', []) || [],
        validation_state:, ready: ready?, teams:, teams_by_id: teams.index_by(&:id),
        automatic: automatic?, editor: editor, coverage: coverage,
        history_page: history_page, history_next: history.length > 10 }.merge(preparation_fields).merge(SourceHistory.new(@batch,
                                                                                                                          @attributes).call)
    end

    alias legacy_review call

    def self.listing(season)
      latest = '(SELECT status FROM departure_acquisitions WHERE departure_batch_id = departure_batches.id ORDER BY id DESC LIMIT 1)'
      DepartureBatch.where(season:).select(:id, :status, Arel.sql("#{latest} AS acquisition_status")).order(id: :desc)
    end

    private

    def operation
      @operation ||= DepartureValidation.where(departure_batch_id: @batch.id).order(:id).last
    end

    def attempt
      @attempt ||= @batch.acquisitions.select(:id, :status, :failure, :started_at, :finished_at).order(:id).last
    end

    def preparation_fields
      plan = @batch.plan
      { preparation: BatchPreparation.form_attributes(plan), capture_only: CapturePreparation.capture_only?(plan) }
    end

    def editor
      key = @attributes[:selection_key]
      return unless key.present? && operation

      DecisionEditor.new(@batch, operation.id.to_s).page(key, @attributes)
    end

    def history_page
      [@attributes[:history_page].to_i, 0].max
    end

    def history_rows
      @history_rows ||= @batch.acquisitions.select(:id, :status, :predecessor_id, :started_at, :finished_at, :failure)
                              .order(id: :desc).offset(history_page * 10).limit(11).to_a
    end

    def coverage
      saved = operation&.choices&.fetch('coverage', nil)
      saved&.merge('review_key' => operation.id.to_s)
    end

    def report
      published = @batch.status == 'published'
      saved = published ? historical_report : operation&.report
      return EMPTY_REPORT.merge(saved || {}) if published || saved.present? || !operation || automatic?

      EMPTY_REPORT.merge('selections' => DecisionInputData.new(operation).selections)
    end

    def historical_report
      OffseasonInputRevision.where(id: @batch.revision_id).pick(Arel.sql("payload->'report'"))
    end

    def teams
      @teams ||= Team.select(:id, :school).order(:school, :id).to_a
    end

    def automatic?
      operation&.choices&.fetch('automatic', false) || DraftTeamReview.applicable?(@batch)
    end

    def ready?
      @batch.status == 'draft' && operation&.status == 'ready' && operation.current? && !operation.approval
    end

    def validation_state
      return operation.review_state if operation

      @batch.status == 'published' ? 'Historical report · validation needed' : 'Validation needed'
    end
  end
end
