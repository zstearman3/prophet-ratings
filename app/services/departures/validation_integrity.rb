# frozen_string_literal: true

module Departures
  # Saved or caller-recomputed digests are never authority; the application secret seals exact content.
  class ValidationIntegrity
    PURPOSE = 'departures-validation-v2'

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end

    def initialize(operation)
      @operation = operation
    end

    def current?
      return published_current? if @operation.status == 'published'

      authentic? && @operation.validator_version == ValidationPreparation::VERSION &&
        @operation.dependency_hash == dependency_hash
    rescue ArgumentError, KeyError, ActiveRecord::RecordNotFound
      false
    end

    def authentic?
      self.class.verifier.verified(@operation.certificate, purpose: 'proposal') == seal
    end

    def sign
      self.class.verifier.generate(seal, purpose: 'proposal')
    end

    def seal
      { 'operation_id' => @operation.id, 'batch_id' => @operation.departure_batch_id,
        'attempt_id' => @operation.departure_acquisition_id, 'normalization_id' => @operation.departure_dataset_normalization_id,
        'validator_version' => @operation.validator_version, 'dependency_hash' => @operation.dependency_hash,
        'artifacts' => @operation.artifacts, 'report_hash' => Contract.digest(@operation.report),
        'choices_hash' => Contract.digest(@operation.choices),
        'proposals_hash' => Contract.digest(@operation.proposals.order(:team_id).pluck(:id, :team_id, :input)) }
    end

    def dependency_hash
      ValidationDependencies.new(@operation.departure_batch_id).digest
    end

    def artifacts
      ValidationArtifacts.new(@operation).call
    end

    def publication_identity
      id = @operation.offseason_input_revision_id
      revision = OffseasonInputRevision.where(id:).pick(:id, :season_id, :kind, :version, :reason, :predecessor_id,
                                                        :input_hash, :dataset_hash, :review_hash)
      { 'operation_id' => @operation.id, 'status' => @operation.status, 'revision' => revision,
        'certificate' => @operation.certificate, 'approval_signature' => @operation.approval&.signature }
    end

    def sign_publication
      self.class.verifier.generate(publication_identity.merge('dependencies' => dependency_hash), purpose: 'publication')
    end

    def publication_receipt
      receipt = self.class.verifier.verified(@operation.publication_receipt, purpose: 'publication')
      Contract.check!(receipt && receipt.except('dependencies') == publication_identity && authentic?,
                      'Departure publication receipt changed; inspect retained history')
      @operation.approval.authenticate
      receipt
    end

    def published_current?
      publication_receipt.fetch('dependencies') == dependency_hash
    end
  end
end
