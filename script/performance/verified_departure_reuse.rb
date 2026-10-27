# frozen_string_literal: true

module OffseasonPerformance
  # Owned fixture setup only: one complete raw validation and exact same-generation copies for real distinct HTTP approvals.
  class VerifiedDepartureReuse
    BATCH_SQL = <<~SQL.squish.freeze
      INSERT INTO departure_batches (season_id, predecessor_id, plan, decisions, acknowledgement, correction_reason, created_at, updated_at)
      SELECT season_id, id, plan, decisions, acknowledgement, 'Synthetic fresh validation and publication', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM departure_batches WHERE id = :original_id RETURNING id
    SQL
    ATTEMPT_SQL = <<~SQL.squish.freeze
      INSERT INTO departure_acquisitions
        (departure_batch_id, predecessor_id, plan, manifest, dataset, evidence, status, failure, started_at, finished_at, created_at, updated_at)
      SELECT :batch_id, id, plan, manifest, dataset, evidence, status, failure, started_at, finished_at, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM departure_acquisitions WHERE departure_batch_id = :original_id ORDER BY id DESC LIMIT 1
    SQL
    EQUALITY_SQL = <<~SQL.squish.freeze
      SELECT (a.plan::text, a.manifest::text, a.dataset::text, a.evidence::text, a.status, a.failure, a.started_at, a.finished_at,
              b.plan::text, b.decisions::text, b.acknowledgement::text, b.season_id, b.status, b.reviewed_by, b.reviewed_at, b.revision_id)
        IS NOT DISTINCT FROM
             (s.plan::text, s.manifest::text, s.dataset::text, s.evidence::text, s.status, s.failure, s.started_at, s.finished_at,
              t.plan::text, t.decisions::text, t.acknowledgement::text, t.season_id, t.status, t.reviewed_by, t.reviewed_at, t.revision_id)
      FROM departure_acquisitions a JOIN departure_batches b ON b.id = a.departure_batch_id
      CROSS JOIN departure_acquisitions s JOIN departure_batches t ON t.id = s.departure_batch_id
      WHERE a.id = :candidate_attempt AND s.id = :source_attempt AND b.id = :candidate_batch AND t.id = :source_batch
    SQL

    def self.clone_cases(original_id, count)
      Fixture.guard!
      Array.new(count) do
        query = ApplicationRecord.sanitize_sql_array([BATCH_SQL, { original_id: }])
        batch_id = ApplicationRecord.connection.select_value(query)
        values = { original_id:, batch_id: }
        ApplicationRecord.connection.execute(ApplicationRecord.sanitize_sql_array([ATTEMPT_SQL, values]))
        Departures::ValidationPreparation.create(DepartureBatch.select(:id).find(batch_id))
      end
    end

    def initialize(source)
      @source = source
    end

    def call(candidate)
      Fixture.guard!
      raise 'Reuse requires a fresh queued case' unless candidate.status == 'queued' && candidate.generation.nil?

      candidate.update!(status: 'running', departure_dataset_normalization_id: @source.departure_dataset_normalization_id)
      projection = Departures::PreparedProposal.new(candidate, reference(candidate)).call
      seal(candidate, projection)
    end

    private

    def reference(candidate)
      id = @source.departure_dataset_normalization_id
      header, revision, summary = DepartureDatasetNormalization.where(id:).pick(Arel.sql("header - 'sources' - 'captures'"),
                                                                                :dataset_revision, :summary)
      raise 'Setup reuse is restricted to the complete legacy corpus' if header['provider']

      header['sources'] = Departures::SourceMetadata.new(candidate.departure_acquisition_id, 'sources')
      DepartureDatasetNormalization::Reference.new(id:, header:, dataset_revision: revision, summary:, source_normalization_ids: {})
    end

    def seal(candidate, projection)
      DepartureValidation.transaction do
        generation = Departures::ValidationPreparation.lock_generation
        @source.reload
        unless @source.status == 'ready' && @source.validator_version == Departures::ValidationPreparation::VERSION &&
               candidate.validator_version == @source.validator_version && @source.generation == generation && !@source.approval
          raise 'Source proof must be ready, current and from this exact generation and validator'
        end

        candidate.with_lock do
          unless candidate.status == 'running' && candidate.departure_dataset_normalization_id == @source.departure_dataset_normalization_id
            raise 'Candidate preparation changed before sealing'
          end
          raise 'Complete candidate content must equal authenticated source proof' unless equal_content?(candidate)

          candidate.update!(status: 'ready', generation:, **projection)
        end
      end
    end

    def equal_content?(candidate)
      values = { candidate_attempt: candidate.departure_acquisition_id, candidate_batch: candidate.departure_batch_id,
                 source_attempt: @source.departure_acquisition_id, source_batch: @source.departure_batch_id }
      ApplicationRecord.connection.select_value(ApplicationRecord.sanitize_sql_array([EQUALITY_SQL, values]))
    end
  end
end
