# frozen_string_literal: true

module Departures
  # Preserves Import's exact-repeat/version identities without loading the annual payload into ActiveRecord.
  class ValidationRevision
    def initialize(approval, batch)
      @approval = approval
      @batch = batch
      @payload = PreparedPayload.new(approval)
    end

    def call
      input_hash = @payload.digest
      revision_id = write_revision(input_hash)
      Contract.check!(PersistedPayload.new(revision_id).digest == input_hash, 'Persisted departure payload differs from approval')
      revision_id
    end

    private

    def attributes(input_hash)
      { season_id: @batch.season_id, version: "departure-batch-#{@batch.id}",
        reason: @batch.correction_reason.presence || 'Approved by admin', predecessor_id: @approval.predecessor_id, input_hash: }
    end

    def revisions
      OffseasonInputRevision.where(season_id: @batch.season_id, kind: 'departures')
    end

    def write_revision(input_hash)
      values = attributes(input_hash)
      existing = revisions.select(:id, :version, :reason, :predecessor_id).find_by(input_hash:)
      return self.class.validate_repeat(existing, values) if existing

      Contract.check!(!revisions.exists?(version: values.fetch(:version)), 'VERSION already exists; use a deliberate successor')
      @payload.insert_revision(values)
    end

    public_class_method def self.validate_repeat(existing, attributes)
      fields = %w[version reason predecessor_id]
      Contract.check!(existing.attributes.slice(*fields) == attributes.stringify_keys.slice(*fields),
                      'Identical inputs already imported with another publication identity')
      existing.id
    end
  end
end
