# frozen_string_literal: true

module Departures
  # Saves ordinary preparation fields and opens explicit acquisition/correction successors.
  class BatchPreparation
    MAX_SOURCES = 200

    def initialize(batch)
      @batch = batch
    end

    def self.create(season, attributes)
      DepartureBatch.transaction do
        batch = DepartureBatch.create!(season:)
        new(batch).save(attributes)
        batch
      end
    end

    def save(attributes)
      batch.with_lock do
        batch.require_editable
        batch.update!(plan: PreparationForm.new(attributes, batch.season).call, decisions: [], acknowledgement: {})
      end
    end

    def acquire
      batch.with_lock { queue_attempt }
    end

    def correct(reason)
      Contract.check!(batch.status == 'published', 'Only published batches can start corrections')
      Contract.text!(reason, 'correction reason')
      DepartureBatch.transaction { correction_draft(reason) }
    end

    def form_attributes
      self.class.form_attributes(batch.plan)
    end

    def self.form_attributes(plan)
      plan.merge('expected_picks' => plan.fetch('expected_picks', []).join(' '),
                 'sources' => plan.fetch('sources', []).index_by { |source| source.fetch('id') })
    end

    private

    attr_reader :batch

    def queue_attempt
      batch.require_editable
      plan = PreparationForm.new(form_attributes, batch.season).call
      attempt = batch.acquisitions.create!(plan:, predecessor: batch.attempt)
      batch.update!(decisions: [], acknowledgement: {})
      attempt
    end

    def correction_draft(reason)
      correction = DepartureBatch.create!(season: batch.season, predecessor: batch, plan: batch.plan,
                                          decisions: batch.decisions, correction_reason: reason)
      correction.acquisitions.create!(batch.attempt.correction_attributes)
      correction
    end
  end
end
