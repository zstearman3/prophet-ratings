# frozen_string_literal: true

module Departures
  # Dependency-row locks serialize direct-SQL invalidation triggers through the whole publication commit.
  class ValidationPublication
    def initialize(approval)
      @approval = approval
      @operation = approval.departure_validation
      @batch = DepartureBatch.select(DepartureBatch.column_names - ['plan']).find(@operation.departure_batch_id)
      @season = @batch.season
    end

    def call
      Season.with_ratings_lock do
        @season.with_lock do
          ValidationPreparation.lock_generation
          publish_locked
        end
      end
    end

    def self.retained_revision(id)
      OffseasonInputRevision.select(OffseasonInputRevision.column_names - ['payload']).find(id)
    end

    private

    def publish_locked
      @operation.with_lock do
        @operation.status == 'published' ? self.class.retained_revision(@operation.offseason_input_revision_id) : publish
      end
    end

    def publish
      validate_current
      ProfilePublication.new(@operation, @season).validate
      revision_id = create_revision
      publish_outputs(revision_id)
      self.class.retained_revision(revision_id)
    end

    def validate_current
      Contract.check!(@operation.status.in?(%w[ready publish_failed]) && @operation.current?, 'Departure dependencies changed; revalidate')
      Contract.check!(@batch.status == 'draft', 'Published departure batches are closed; start a correction')
      Contract.check!(@approval.document['decision'] == 'approved' && @approval.reviewed_by.present?, 'Require explicit approval')
      latest = OffseasonInputRevision.where(season: @season, kind: 'departures').maximum(:id)
      Contract.check!(latest == @approval.predecessor_id, 'Departure predecessor changed; revalidate')
    end

    def create_revision
      payload = PreparedPayload.new(@approval)
      input_hash = payload.digest
      revision_id = insert_revision(payload, input_hash)
      self.class.verify_payload(revision_id, input_hash)
      revision_id
    end

    public_class_method def self.verify_payload(revision_id, input_hash)
      Contract.check!(PersistedPayload.new(revision_id).digest == input_hash,
                      'Persisted departure payload hash differs from approved inputs')
    end

    def publish_outputs(revision_id)
      ProfilePublication.new(@operation, @season).link(revision_id)
      publish_batch(revision_id)
      @operation.update!(status: 'published', offseason_input_revision_id: revision_id, error: nil,
                         published_generation: ValidationPreparation.generation)
    end

    def publish_batch(revision_id)
      PublishedBatch.new(@approval, @batch).call(revision_id)
    end

    def insert_revision(payload, input_hash)
      payload.insert_revision(season_id: @season.id, version: "departure-batch-#{@batch.id}",
                              reason: @batch.correction_reason.presence || 'Approved by admin',
                              predecessor_id: @approval.predecessor_id, input_hash:)
    end
  end
end
