# frozen_string_literal: true

module OffseasonPerformance
  # Fresh distinct corrections measure real approval requests and a separate first publication worker.
  module DepartureValidationDriver
    PHASES = %w[validate old-serial old-concurrent draft-serial draft-concurrent status confirm publish revalidate].freeze

    def self.call(result, scenario, clients)
      load_helpers
      case scenario.phase
      when 'validate' then DepartureValidationSetup.new(scenario.fixture).call(result)
      when 'publish' then publish(result, clients.first)
      when 'revalidate' then DepartureRevalidationWindow.new(clients.first).call(result)
      else DepartureValidationHttp.new(scenario, clients).call(result)
      end
    end

    # The host CLI needs phase names before Rails boots; these helpers require the Rails driver environment.
    def self.load_helpers
      require_relative 'verified_departure_reuse'
      require_relative 'departure_validation_http'
      require_relative 'departure_revalidation_window'
      require_relative 'departure_validation_setup'
      require_relative 'departure_payload_oracle'
    end

    def self.database_bytes
      ApplicationRecord.connection.select_value('SELECT pg_database_size(current_database())').to_i
    end

    def self.verify_proposal(operation, record, fixture)
      raise 'Original corpus digest changed' unless record.dataset_revision == fixture.fetch('dataset_digest')

      expected = fixture.fetch('cardinalities').fetch('school_capture_observations')
      raise 'Original production corpus incomplete' unless record.summary.fetch('production') == expected

      verify_sources(record.id, expected + 1)
      raise 'All picks must be accounted' unless operation.report.fetch('accounted_selections') == 60
      raise 'Every team must have a proposal' unless operation.proposals.count == 365
    end

    def self.verify_sources(id, expected)
      template = <<~SQL.squish
        SELECT count(*) AS count, count(s.id) AS normalized, bool_and(s.status = 'completed') AS completed FROM departure_dataset_normalizations n,
          LATERAL jsonb_each_text(n.source_normalization_ids) entries(key, value)
          LEFT JOIN departure_source_normalizations s ON s.id = value::bigint WHERE n.id = :id
      SQL
      query = ApplicationRecord.sanitize_sql_array([template, { id: }])
      row = ApplicationRecord.connection.exec_query(query).first
      return if row.fetch('count') == expected && row.fetch('normalized') == expected && row.fetch('completed')

      raise 'Original sources must all be authenticated'
    end

    def self.wait(id)
      DepartureNormalizationDriver.wait(id)
    rescue StandardError => error
      retained = GoodJob::Job.find_by(active_job_id: id)&.error
      raise "#{error.message}; retained worker error: #{retained.to_s.first(2000)}"
    end

    def self.publish(result, client)
      cases = JSON.parse(File.read('/benchmark/departure-validation-cases.json'))
      operation = DepartureValidation.find(cases.fetch('operation_ids').last)
      before = OffseasonInputRevision.maximum(:id)
      state = request_publication(operation, client)
      result['approval_request'] = state.fetch(:request)
      result['worker'] = wait(state.fetch(:job).active_job_id)
      verify_publication(operation.reload, state.fetch(:approval), before)
      finish_publication(result, cases, operation, state)
    end

    def self.request_publication(operation, client)
      raise 'Cannot benchmark a published or preapproved shortcut' unless operation.status == 'ready' && !operation.approval

      request = DepartureValidationHttp.confirm(client, operation)
      approval = DepartureApproval.find_by!(departure_validation_id: operation.id)
      job = GoodJob::Job.where(job_class: 'PublishDepartureValidationJob', queue_name: JobDriver.queue).order(created_at: :desc).first!
      { request:, approval:, job: }
    end

    def self.finish_publication(result, cases, operation, state)
      result['worker_terminal_before_oracle'] = Measurements.worker_current
      result['full_corpus_oracle'] = DeparturePayloadOracle.call(cases.fetch('original_id'), operation, state.fetch(:approval))
      result.merge!('operation_id' => operation.id, 'revision_id' => operation.offseason_input_revision_id, 'status' => operation.status,
                    'profile_pointers' => 365, 'job_arguments' => state.fetch(:job).serialized_params.fetch('arguments'))
    end

    def self.verify_publication(operation, approval, before)
      revision_id = operation.offseason_input_revision_id
      unless operation.status == 'published' && revision_id.to_i > before.to_i
        raise "New immutable revision not created: #{operation.status}: #{operation.error}"
      end
      raise 'Missing profile pointers' unless TeamOffseasonProfile.where(departure_revision_id: revision_id).count == 365
      raise 'Missing approval audit' unless approval.reviewed_by.present? && approval.reviewed_at.present? && approval.user_id
    end
  end
end
