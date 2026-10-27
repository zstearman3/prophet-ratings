# frozen_string_literal: true

module Departures
  # Resolves only submitted captured identities; browser-supplied numeric facts never enter the dataset.
  class DecisionInputData
    def initialize(operation)
      @record_id = self.class.normalization_id(operation)
    end

    def self.normalization_id(operation)
      fields = operation.attributes
      fields['departure_dataset_normalization_id'] || DepartureValidation
        .where(departure_batch_id: fields['departure_batch_id'], departure_acquisition_id: fields['departure_acquisition_id'])
        .where.not(departure_dataset_normalization_id: nil).order(id: :desc).pick(:departure_dataset_normalization_id)
    end

    attr_reader :record_id

    def call(rows)
      entries = rows.values
      Contract.check!(entries.all?(Hash), 'Invalid departure choices')
      stints = self.class.stints(entries)
      projection(entries, stints)
    end

    def selections
      DepartureDatasetRow.where(departure_dataset_normalization_id: @record_id, kind: 'selections').order(:ordinal).pluck(:fact)
    end

    def sources(ids)
      return [] if ids.empty?

      self.class.validate_ids(ids)
      query = source_relation(ids)
      ApplicationRecord.connection.exec_query(query.to_sql).map { |row| JSON.parse(row.fetch('value')) }
    end

    def source_relation(ids)
      source = Arel.sql("departure_dataset_normalizations, LATERAL jsonb_array_elements(header->'sources') AS sources(value)")
      DepartureDatasetNormalization.from(source).where(id: @record_id).where("value->>'id' IN (?)", ids).select(Arel.sql('value'))
    end

    def self.validate_ids(ids)
      Contract.check!(ids.all?(String), 'Invalid evidence source choices')
    end

    def self.production_keys(stints)
      keys = stints.select { |row| DecisionForm.selected_stint?(row) }.pluck('production_key')
      Contract.check!(keys.all?(String), 'Invalid captured production identity')
      keys
    end

    def self.stints(entries)
      values = entries.map { |entry| entry.fetch('stints', {}) }
      Contract.check!(values.all?(Hash), 'Invalid captured production choices')
      values.flat_map(&:values)
    end

    private

    def projection(entries, stints)
      form = self.class
      ids = entries.flat_map { |row| Array(row['evidence_source_ids']) } + form.identity_ids(stints)
      keys = form.production_keys(stints)
      header.merge('selections' => selections, 'production' => ProductionChoices.new(@record_id).tables(keys),
                   'sources' => sources(ids.compact_blank.uniq))
    end

    def header
      DepartureDatasetNormalization.where(id: @record_id).pick(Arel.sql("header - 'sources' - 'captures'"))
    end

    public_class_method def self.identity_ids(stints)
      Contract.check!(stints.all?(Hash), 'Invalid captured stint choices')
      stints.flat_map { |row| Array(row['identity_evidence_source_ids']) }
    end
  end
end
