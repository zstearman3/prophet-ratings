# frozen_string_literal: true

module Departures
  # Saves ordinary preparation fields and opens explicit acquisition/correction successors.
  class BatchPreparation
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

    def acquire(attributes = {})
      batch.with_lock do
        close_interrupted if attributes['close_interrupted'] == '1'
        queue_attempt
      end
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
      plan.except('sources').merge('expected_picks' => plan.fetch('expected_picks', []).join(' '),
                                   'absent_postseason_team_ids' => plan.fetch('absent_postseason_team_ids', []).join(' '))
    end

    private

    attr_reader :batch

    def close_interrupted
      current = batch.attempt
      Contract.check!(batch.status == 'draft' && current&.status == 'running', 'Only a running draft attempt can be closed')
      current.with_lock do
        current.update!(status: 'failed', failure: 'Operator confirmed interrupted acquisition; retained bytes preserved',
                        finished_at: Time.current)
      end
    end

    def queue_attempt
      batch.require_editable
      require_provider
      attempt = batch.acquisitions.create!(plan: PreparationForm.new(form_attributes, batch.season).call, predecessor: batch.attempt)
      batch.update!(decisions: [], acknowledgement: {})
      attempt
    end

    def require_provider
      Contract.check!(batch.plan['provider'] == 'cbbd', 'Legacy HTML acquisition is read-only; create a CBBD successor')
    end

    def correction_draft(reason)
      correction = DepartureBatch.create!(season: batch.season, predecessor: batch, plan: batch.plan,
                                          decisions: batch.decisions, correction_reason: reason)
      correction.acquisitions.create!(batch.attempt.correction_attributes)
      correction
    end
  end
end
