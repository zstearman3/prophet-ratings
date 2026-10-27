# frozen_string_literal: true

module Departures
  # One team at a time follows the existing CBBD rules; legacy source observations retain their original order.
  class AnnualRowWriter
    def initialize(record, sources)
      @record = record
      @sources = sources
    end

    def call
      record.with_lock do
        next if record.status == 'completed'

        @settings = record.header
        populate
        complete
      end
    end

    def append(kind, facts)
      ordinal = record.rows.where(kind:).count
      facts.each do |fact|
        ordinal += 1
        create_row(kind, ordinal, fact)
      end
    end

    def create_row(kind, ordinal, fact)
      EvidenceRows.annual(departure_dataset_normalization_id: record.id, kind:, ordinal:, fact:)
    end

    private

    attr_reader :record, :sources, :settings

    def populate
      DepartureDatasetRow.where(departure_dataset_normalization_id: record.id).delete_all
      append('failures', settings.fetch('sources').select { |source| source['failure'].present? })
      settings['schema'] == CbbdDataset::VERSION ? cbbd : legacy
    end

    def complete
      summary = DatasetStream::KINDS.index_with { |kind| record.rows.where(kind:).count }
      record.update!(status: 'completed', dataset_revision: DatasetStream.new(record).digest, summary:)
    end

    def cbbd
      append('selections', selections)
      write_teams
    rescue ArgumentError, KeyError => error
      fail_production(error)
    end

    def write_teams
      require_complete_sources
      team_ids.each { |team_id| append_team(team_id) }
    end

    def fail_production(error)
      record.rows.where(kind: %w[production production_warnings]).delete_all
      append('failures', [{ 'id' => 'normalization', 'failure' => error.message }])
    end

    def require_complete_sources
      failure = sources.values.find { |source| source.status != 'completed' }
      Contract.check!(!failure, failure&.failure)
    end

    def selections
      rows = sources['draft'] ? sources.fetch('draft').rows.order(:ordinal).pluck(:fact) : []
      CbbdSelections.new(rows, settings).call
    end

    def team_ids
      ids = sources.values.map(&:id)
      DepartureNormalizedRow.where(departure_source_normalization_id: ids).where.not(provider_team_id: nil)
                            .distinct.order(:provider_team_id).pluck(:provider_team_id)
    end

    def append_team(team_id)
      parsed = settings.fetch('sources').map do |source|
        source.merge('rows' => self.class.team_rows(sources[source['id']], team_id))
      end
      production = CbbdProduction.new(parsed:, settings:).call
      append('production', production)
      append('production_warnings', CbbdProduction.warnings(production)) if CbbdDataset.reported_totals?(settings)
    end

    public_class_method def self.team_rows(source, team_id)
      source ? source.rows.where(provider_team_id: team_id).order(:ordinal).skip_query_cache!.pluck(:fact) : []
    end

    def legacy
      settings.fetch('sources').each { |source| append_legacy(source) }
    end

    public_class_method def self.legacy_kind(source)
      source['type'] == 'nba_results' ? 'selections' : 'production'
    end

    def append_legacy(source)
      normalization = sources[source['id']]
      return unless normalization

      kind = self.class.legacy_kind(source)
      normalization.rows.order(:ordinal).find_each(batch_size: JsonRows::BATCH_SIZE) { |row| append(kind, [row.fact]) }
    end
  end
end
