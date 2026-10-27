# frozen_string_literal: true

module Departures
  # Saves substantive decisions, then requires fresh worker validation before approval.
  class DecisionEditor
    def initialize(batch, review_key)
      @batch = batch
      @review_key = review_key
      @operation = nil
    end

    def page(key, attributes)
      validate_operation
      selection = selection(key)
      decision = self.class.index_decisions(@batch.decisions)[key] || {}
      page_choices(decision, attributes).merge(selection:, decision:, review_key: @review_key)
    end

    def save(attributes)
      ValidationLocks.web_transaction { locked_save(attributes) }
      ValidationPreparation.queue(@batch)
    end

    def self.index_decisions(rows)
      rows.index_by { |row| row.fetch('selection_key') }
    end

    def self.selected_keys(decision)
      decision.fetch('stints', []).map { |stint| PlayerIdentity.choice(stint, stint) }
    end

    private

    def operation
      @operation ||= DepartureValidation.where(departure_batch_id: @batch.id).order(:id).last
    end

    def input_data
      DecisionInputData.new(operation)
    end

    def selection(key)
      selection = input_data.selections.find { |row| row.fetch('selection_key') == key }
      Contract.check!(selection, 'Unknown departure selection')
      selection
    end

    def page_choices(decision, attributes)
      production = ProductionChoices.new(input_data.record_id)
      choices = production.page(attributes)
      choices[:production_options] =
        (production.selected_options(self.class.selected_keys(decision)) + choices.fetch(:production_options)).uniq
      choices.merge(sources: evidence_choices(decision, attributes))
    end

    def evidence_choices(decision, attributes)
      selected = input_data.sources(PreparedDataset.decision_evidence(decision).uniq)
      (selected + SourceHistory.new(@batch, attributes).call.fetch(:sources)).uniq { |source| source.fetch('id') }
    end

    def locked_save(attributes)
      @batch = DepartureBatch.select(DepartureBatch.column_names - ['plan']).lock('FOR UPDATE NOWAIT').find(@batch.id)
      validate_operation
      save_rows(attributes.fetch('rows'))
    end

    def save_rows(rows)
      Contract.check!(rows.is_a?(Hash) && rows.any? && rows.length <= input_data.selections.length, 'Choose captured departure selections')
      decisions = DecisionForm.new(input_data.call(rows)).call(rows)
      @batch.update!(decisions: merged_decisions(decisions, rows.keys), acknowledgement: {})
    end

    def merged_decisions(decisions, keys)
      retained = self.class.index_decisions(@batch.decisions).except(*keys)
      all = retained.merge(DecisionEditor.index_decisions(decisions))
      input_data.selections.filter_map { |selection| all[selection.fetch('selection_key')] }
    end

    def validate_operation
      latest = DepartureValidation.where(departure_batch_id: @batch.id).maximum(:id)
      Contract.check!(@batch.status == 'draft' && operation && latest.to_s == @review_key && operation.id == latest &&
                      input_data.record_id && !operation.choices['automatic'],
                      'Departure choices changed; reload and review again')
      attempt = @batch.acquisitions.order(id: :desc).pick(:id)
      Contract.check!(attempt == operation.departure_acquisition_id, 'Departure acquisition changed; validate again')
    end
  end
end
