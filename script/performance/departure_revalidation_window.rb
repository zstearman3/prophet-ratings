# frozen_string_literal: true

module OffseasonPerformance
  # Measures actual revalidation submissions while preserving the earlier held approvals.
  class DepartureRevalidationWindow
    def initialize(client)
      @client = client
      @cases = JSON.parse(File.read('/benchmark/departure-validation-cases.json'))
    end

    def call(result)
      baseline = retained_state
      batches = @cases.fetch('batch_ids').first(40)
      raise 'Forty independent revalidation cases required' unless batches.uniq.length == 40

      before = DepartureValidation.maximum(:id)
      samples = batches.map { |id| submit(id) }
      verify_queued(batches, before)
      raise 'Revalidation changed approvals, held publication jobs, revisions or pointers' unless retained_state == baseline

      result['warmups'] = samples.first(10)
      result['samples'] = samples.drop(10)
      result['revalidation'] = { 'distinct_new_operations' => 40, 'distinct_new_jobs' => 40,
                                 'approval_revision_pointer_changes' => 0, 'raw_validations_executed' => 0 }
      Measurements.check(result, limit: 1)
    end

    private

    def submit(id)
      DepartureValidationHttp.request(@client, "/admin/departure_batches/#{id}/revalidate", method: Net::HTTP::Post) do |response|
        response.code.to_i == 302
      end
    end

    def retained_state
      [DepartureApproval.order(:id).pluck(:id, :review_hash, :document, :reviewed_at, :user_id),
       OffseasonInputRevision.order(:id).pluck(:id, :input_hash),
       TeamOffseasonProfile.order(:id).pluck(:id, :departure_revision_id),
       GoodJob::Job.where(job_class: 'PublishDepartureValidationJob').order(:id).pluck(:id, :performed_at, :finished_at)]
    end

    def valid_operations?(operations, batches)
      operations.count == 40 && operations.pluck(:departure_batch_id).sort == batches.sort && operations.pluck(:status).uniq == ['queued']
    end

    def verify_queued(batches, before)
      operations = DepartureValidation.where(departure_batch_id: batches).where('id > ?', before).order(:id)
      valid = valid_operations?(operations, batches)
      jobs = GoodJob::Job.where(job_class: 'PrepareDepartureValidationJob', queue_name: JobDriver.queue).to_a
      expected = operations.pluck(:id).zip
      arguments = jobs.map { |job| job.serialized_params.fetch('arguments') }
      valid &&= jobs.length == 40 && arguments.sort == expected.sort && jobs.all? { |job| job.performed_at.nil? && job.finished_at.nil? }
      raise 'Expected forty new scalar-ID preparation jobs held on this owned phase queue' unless valid
    end
  end
end
