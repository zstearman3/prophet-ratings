# frozen_string_literal: true

module Departures
  # Keep old offline datasets canonical while publication uses its separate freshly authenticated projection.
  class ValidationDatasetRetention
    def initialize(operation)
      @operation = operation
      @reference = nil
      @identity = nil
    end

    def pending?
      DepartureAcquisition.where(id: attempt_id, departure_batch_id: @operation.departure_batch_id)
                          .exists?(["dataset->>'storage_version' = ? AND predecessor_id < id", 'departure-validation-pending-v1'])
    end

    def prepare
      return unless pending? && DepartureAcquisition.where(id: attempt_id).where("manifest->>'provider' = 'cbbd'").exists?

      @identity = ValidationArtifacts.new(@operation).retained
      @reference = StoredDataset.reference(StoredDataset.new(DepartureAcquisition.find(attempt_id)).call)
    end

    def call
      return unless pending?

      validate_identity
      record = DepartureDatasetNormalization.select(:id, :dataset_revision, :summary, Arel.sql("header - 'sources' - 'captures' AS header"))
                                            .find(@operation.departure_dataset_normalization_id)
      PreparedDataset.new(record).retain(attempt_id, expression: retained_sql(record))
    end

    private

    def attempt_id
      @operation.departure_acquisition_id
    end

    def validate_identity
      Contract.check!(!@reference || @identity == ValidationArtifacts.new(@operation).retained,
                      'Departure canonical evidence changed during preparation; revalidate')
    end

    def retained_sql(record)
      return PreparedDataset.new(record).sql unless @reference

      ApplicationRecord.sanitize_sql_array(['?::jsonb', JSON.generate(@reference)])
    end
  end
end
