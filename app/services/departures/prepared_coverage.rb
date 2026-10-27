# frozen_string_literal: true

module Departures
  # Coverage choices are derived once in the worker from authenticated normalized rows.
  class PreparedCoverage
    def initialize(record)
      @record = record
    end

    def call
      header = @record.header
      return unless header['provider'] == 'cbbd'

      sources = header.fetch('sources')
      { 'selections' => facts('selections'), 'sources' => source_summary(sources), 'no_postseason_teams' => absences(sources),
        'production_warnings' => facts('production_warnings'), 'errors' => [], 'fields' => CoverageReview.form_fields(header) }
    end

    private

    def facts(kind)
      @record.rows.where(kind:).order(:ordinal).pluck(:fact)
    end

    def source_summary(sources)
      sources.map { |source| self.class.summarize(source, @record.source_normalization_ids) }
    end

    public_class_method def self.summarize(source, ids)
      source.merge('row_count' => DepartureSourceNormalization.where(id: ids[source.fetch('id')]).pick(:row_count))
    end

    def absences(sources)
      return [] unless CoverageEvidence.postseason_succeeded?(sources)

      @record.rows.where(kind: 'production').order(:ordinal).skip_query_cache!.find_each(batch_size: JsonRows::BATCH_SIZE)
             .filter_map { |row| self.class.absence(row.fact) }
    end

    public_class_method def self.absence(table)
      CoverageEvidence.named_team(table) if CoverageEvidence.eligible_absence?(table)
    end
  end
end
