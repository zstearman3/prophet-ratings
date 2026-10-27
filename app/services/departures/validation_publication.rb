# frozen_string_literal: true

module Departures
  # Raw bytes and staged facts are reauthenticated under table locks before one atomic publication.
  class ValidationPublication
    def initialize(approval)
      @approval = approval
      @operation = approval.departure_validation
      @batch = DepartureBatch.select(DepartureBatch.column_names - ['plan']).find(@operation.departure_batch_id)
      @season = @batch.season
    end

    def call
      @operation.offseason_input_revision_id ? retained_revision : locked_publication
    rescue ArgumentError => error
      fail_publication(error)
      raise
    end

    def retained_revision
      ValidationIntegrity.new(@operation).publication_receipt
      OffseasonInputRevision.select(OffseasonInputRevision.column_names - ['payload']).find(@operation.offseason_input_revision_id)
    end

    private

    def locked_publication
      Season.with_ratings_lock { @season.with_lock { ValidationLocks.lock { publish_locked } } }
    end

    def published?
      @operation.status == 'published'
    end

    def fail_publication(error)
      @operation.reload
      @operation.update!(status: 'stale', error: error.message) unless published?
    end

    def publish_locked
      @operation.reload
      @approval.reload
      @batch = DepartureBatch.select(DepartureBatch.column_names - ['plan']).find(@batch.id)
      published? ? retained_revision : publish
    end

    def publish
      validate_current
      ProfilePublication.new(@operation, @season).validate
      revision_id = ValidationRevision.new(@approval, @batch).call
      publish_outputs(revision_id)
      retained_revision
    end

    def publish_outputs(revision_id)
      ProfilePublication.new(@operation, @season).link(revision_id)
      publish_batch(revision_id)
      @operation.update!(status: 'published', offseason_input_revision_id: revision_id, error: nil)
      @operation.update!(publication_receipt: ValidationIntegrity.new(@operation).sign_publication)
    end

    def validate_current
      Contract.check!(@operation.status.in?(%w[ready publish_failed]) && @operation.current?, 'Departure dependencies changed; revalidate')
      @approval.authenticate
      validate_predecessor
      Contract.check!(ValidationArtifacts.new(@operation).call == @operation.artifacts, 'Departure retained artifacts changed; revalidate')
    end

    def validate_predecessor
      Contract.check!(@batch.status == 'draft', 'Published departure batches are closed; start a correction')
      latest = OffseasonInputRevision.where(season: @season, kind: 'departures').maximum(:id)
      Contract.check!(latest == @approval.predecessor_id, 'Departure predecessor changed; revalidate')
    end

    def publish_batch(revision_id)
      document = @approval.document
      @batch.update!(status: 'published', revision_id:, decisions: document.fetch('decisions'),
                     reviewed_by: @approval.reviewed_by, reviewed_at: @approval.reviewed_at,
                     acknowledgement: document.fetch('partial_acknowledgement', {}))
    end
  end
end
