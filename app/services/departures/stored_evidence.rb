# frozen_string_literal: true

module Departures
  # Explicit database-reference adapter; the legacy file/base64 reader keeps its original contract.
  class StoredEvidence < RetainedEvidence
    def dataset
      DatasetStream.new(StoredDataset.new(attempt).call).expand
    end

    def captured_sources
      normalized = StoredDataset.new(attempt).parsed_sources
      attempt.manifest.fetch('sources').map do |source|
        self.class.source_result(source, normalized[source['id']])
      end
    end

    def self.source_result(source, normalization)
      result = source.merge('rows' => rows(normalization))
      return result unless normalization && normalization.status != 'completed'

      result.merge('failure' => normalization.failure.presence || 'Source normalization is not complete')
    end

    def self.rows(source)
      source&.status == 'completed' ? source.rows.order(:ordinal).pluck(:fact) : []
    end

    def acquisition_result
      plan = attempt.plan
      return capture_result if CapturePreparation.capture_only?(plan)

      record = StoredDataset.new(attempt).call
      { dataset: StoredDataset.reference(record), status: self.class.status(record, plan) }
    end

    def self.status(record, plan)
      complete = record.summary.fetch('failures').zero? && BatchAcquisition.picks_complete?(actual_picks(record),
                                                                                            plan.fetch('expected_picks'))
      complete ? 'completed' : 'incomplete'
    end

    def self.actual_picks(record)
      record.rows.where(kind: 'selections').pluck(Arel.sql("(fact->>'overall_pick')::integer"))
    end

    def verified_dataset(plan)
      Contract.check!(attempt.plan == plan, 'Preparation changed; request a new acquisition')
      record = verified_record
      StoredDataset.new(attempt).verify(record)
      DatasetStream.new(record).expand
    end

    def bytes(source_id)
      CaptureStore.new(attempt).bytes(source_id, source(source_id))
    end

    def with_paths(review)
      materialize do |directory|
        paths = self.class.paths(directory).merge(departure_attempt_id: attempt.id)
        Contract.write(paths.fetch(:dataset_path), dataset)
        Contract.write(paths.fetch(:review_path), review)
        yield paths
      end
    end

    private

    def capture_result
      sources = StoredDataset.new(attempt).parsed_sources
      failed = sources.values.any? { |source| source.status != 'completed' } || failed_sources?
      { dataset: {}, status: failed ? 'incomplete' : 'completed' }
    end

    def failed_sources?
      attempt.manifest.fetch('sources').any? { |source| source['failure'].present? }
    end

    def verified_record
      saved = attempt.dataset
      Contract.check!(attempt.terminal? && saved['storage_version'] == StoredDataset::VERSION,
                      'Acquire usable evidence before reviewing decisions')
      record = StoredDataset.new(attempt).call
      Contract.check!(record.id == saved.fetch('normalization_id') && record.dataset_revision == saved.fetch('dataset_revision'),
                      'Departure normalization reference mismatch')
      record
    end
  end
end
