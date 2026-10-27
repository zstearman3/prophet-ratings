# frozen_string_literal: true

module OffseasonPerformance
  # The first slice measures real full-source validation and a genuinely new complete publication.
  module DepartureValidationDriver
    PHASES = %w[validate publish].freeze

    def self.call(result, scenario, _clients)
      require_relative 'departure_payload_oracle'
      scenario.phase == 'validate' ? validate(result, scenario.fixture) : publish(result)
    end

    def self.database_bytes
      ApplicationRecord.connection.select_value('SELECT pg_database_size(current_database())').to_i
    end

    def self.wait(id)
      DepartureNormalizationDriver.wait(id)
    end

    def self.clone_batch(original_id)
      Fixture.guard!
      sql = <<~SQL.squish
        INSERT INTO departure_batches (season_id, predecessor_id, plan, decisions, acknowledgement, correction_reason, created_at, updated_at)
        SELECT season_id, id, plan, decisions, acknowledgement, 'Synthetic fresh validation and publication', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM departure_batches WHERE id = #{Integer(original_id)} RETURNING id
      SQL
      id = ApplicationRecord.connection.select_value(sql)
      sql = <<~SQL.squish
        INSERT INTO departure_acquisitions
          (departure_batch_id, predecessor_id, plan, manifest, dataset, evidence, status, started_at, finished_at, created_at, updated_at)
        SELECT #{Integer(id)}, id, plan, manifest, dataset, evidence, status, started_at, finished_at, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM departure_acquisitions WHERE departure_batch_id = #{Integer(original_id)} ORDER BY id DESC LIMIT 1
      SQL
      ApplicationRecord.connection.execute(sql)
      DepartureBatch.select(:id).find(id)
    end

    def self.validate(result, fixture)
      operation = Departures::ValidationPreparation.create(clone_batch(fixture.fetch('departure_id')))
      job = PrepareDepartureValidationJob.perform_later(operation.id)
      result['worker'] = wait(job.job_id)
      finish_validation(result, operation.reload, fixture, job)
    end

    def self.finish_validation(result, operation, fixture, job)
      raise "Validation #{operation.status}: #{operation.error}" unless operation.status == 'ready'

      record = DepartureDatasetNormalization.select(:id, :dataset_revision, :summary).find(operation.departure_dataset_normalization_id)
      verify_proposal(operation, record, fixture)
      File.write('/benchmark/departure-validation-cases.json',
                 JSON.generate('original_id' => fixture.fetch('departure_id'), 'operation_id' => operation.id))
      result.merge!('operation_id' => operation.id, 'status' => operation.status, 'dataset_revision' => record.dataset_revision,
                    'summary' => record.summary, 'proposals' => operation.proposals.count, 'job_arguments' => job.arguments)
    end

    def self.verify_proposal(operation, record, fixture)
      raise 'Original corpus digest changed' unless record.dataset_revision == fixture.fetch('dataset_digest')

      expected = fixture.fetch('cardinalities').fetch('school_capture_observations')
      raise 'All original production rows required' unless record.summary.fetch('production') == expected
      raise 'All target teams required' unless operation.proposals.count == 365
      raise 'All picks required' unless operation.report.fetch('accounted_selections') == 60
    end

    def self.publish(result)
      cases = JSON.parse(File.read('/benchmark/departure-validation-cases.json'))
      operation = DepartureValidation.find(cases.fetch('operation_id'))
      user = User.find_by!(admin: true)
      approval = Departures::ValidationApproval.new(operation).call(reviewer: user.email, user:)
      publish_approval(result, cases, approval)
    end

    def self.publish_approval(result, cases, approval)
      before = OffseasonInputRevision.maximum(:id)
      job = PublishDepartureValidationJob.perform_later(approval.id)
      result['worker'] = wait(job.job_id)
      operation = approval.departure_validation.reload
      verify_publication(operation, before)
      finish_publication(result, cases, operation, approval, job)
    end

    def self.verify_publication(operation, before)
      count = TeamOffseasonProfile.where(departure_revision_id: operation.offseason_input_revision_id).count
      return if operation.status == 'published' && operation.offseason_input_revision_id > before && count == 365

      raise "First publication incomplete: #{operation.status}: #{operation.error}"
    end

    def self.finish_publication(result, cases, operation, approval, job)
      result['worker_terminal_before_oracle'] = Measurements.worker_current
      result['full_corpus_oracle'] = DeparturePayloadOracle.call(cases.fetch('original_id'), operation, approval)
      result.merge!('operation_id' => operation.id, 'revision_id' => operation.offseason_input_revision_id, 'status' => operation.status,
                    'profile_pointers' => 365, 'job_arguments' => job.arguments,
                    'approval_id' => approval.id, 'actor_id' => approval.user_id)
    end
  end
end
