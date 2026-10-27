# frozen_string_literal: true

module OffseasonPerformance
  # Normal authenticated HTTP routes run with ordinary caches and the same web/worker caps as the original baseline.
  class DepartureValidationHttp
    def initialize(scenario, clients)
      @scenario = scenario
      @clients = clients
      @cases = JSON.parse(File.read('/benchmark/departure-validation-cases.json'))
    end

    def call(result)
      @scenario.phase == 'confirm' ? confirmation_window(result) : read_window(result)
      Measurements.check(result, limit: concurrent? ? 2 : 1)
      check_cold(result) unless @scenario.phase.in?(%w[confirm status])
    end

    def self.request(client, path, method: Net::HTTP::Get, values: {}, &valid)
      id = SecureRandom.hex(12)
      started_at = Time.now.to_f
      response = nil
      elapsed = Benchmark.realtime { response = client.request(method, path, values:, id:) }
      metrics = Measurements.http(response, id,
                                  { 'elapsed' => elapsed, 'valid' => yield(response), 'scenario' => 'departure_validation' })
      metrics.merge('started_at' => started_at, 'finished_at' => Time.now.to_f)
    end

    def self.confirm(client, operation)
      path = "/admin/departure_batches/#{operation.departure_batch_id}/publish"
      values = { 'review[review_key]' => operation.id.to_s, 'review[confirm]' => '1' }
      request(client, path, method: Net::HTTP::Patch, values:) { |response| response.code.to_i == 302 }
    end

    private

    def concurrent?
      @scenario.phase.end_with?('-concurrent')
    end

    def read_window(result)
      result['cold'] = read(@clients.first) unless @scenario.phase == 'status'
      result['warmups'] = requests(10)
      result['samples'] = requests(30)
    end

    def requests(count)
      return Array.new(count) { read(@clients.first) } unless concurrent?

      queue = Driver.request_queue(count)
      @clients.map { |client| Thread.new { consume(client, queue) } }.flat_map(&:value).sort_by { |row| row.fetch('ordinal') }
    end

    def consume(client, queue)
      values = []
      while (index = Driver.pop(queue))
        values << read(client).merge('ordinal' => index)
      end
      values
    end

    def read(client)
      original = @scenario.phase.start_with?('old-')
      id = original ? @cases.fetch('original_id') : @cases.fetch('batch_ids').first
      path = "/admin/departure_batches/#{id}#{'/progress' if @scenario.phase == 'status'}"
      self.class.request(client, path) { |response| valid_read?(response, original) }
    end

    def valid_read?(response, original)
      return false unless response.code.to_i == 200
      return JSON.parse(response.body).fetch('status') == 'ready' if @scenario.phase == 'status'

      response.body.include?('Pick 60') && response.body.include?(original ? 'Historical report' : 'Validation ready')
    end

    def check_cold(result)
      cold = result['cold']
      result.fetch('failures') << 'invalid or missing cold GET measurements' unless Measurements.valid_cold?(cold)
      result.fetch('failures') << 'cold GET exceeds 3s' if cold && cold.fetch('elapsed') > 3
    end

    def confirmation_window(result)
      baseline = publication_state
      operations = @cases.fetch('operation_ids').first(40).map { |id| DepartureValidation.find(id) }
      raise 'Distinct unpublished cases required' unless operations.map(&:id).uniq.length == 40 && operations.none?(&:approval)

      samples = operations.map do |operation|
        sample = self.class.confirm(@clients.first, operation)
        verify_approval(operation)
        raise 'Approval request published inputs synchronously' unless publication_state == baseline

        sample
      end
      result['warmups'] = samples.first(10)
      result['samples'] = samples.drop(10)
      verify_queued(operations)
      result['approvals'] = { 'distinct_new_approvals' => 40, 'distinct_new_jobs' => 40, 'revisions_or_pointer_changes' => 0,
                              'audit' => 'user/time/exact document/canonical review hash verified for every request' }
    end

    def publication_state
      [OffseasonInputRevision.order(:id).pluck(:id, :input_hash), TeamOffseasonProfile.order(:id).pluck(:id, :departure_revision_id)]
    end

    def verify_approval(operation)
      approval = DepartureApproval.find_by!(departure_validation_id: operation.id)
      actor = User.find_by!(email: 'benchmark@example.test')
      raise 'Approval must retain the authenticated actor' unless approval.user_id == actor.id && approval.reviewed_by == actor.email
      raise 'Fixture complete coverage changed' unless operation.report.fetch('gaps').empty?

      expected = operation.choices.fetch('review').merge('reviewed_by' => actor.email, 'reviewed_at' => approval.reviewed_at.iso8601(6),
                                                         'partial_acknowledgement' => {})
      return if approval.document == expected && approval.review_hash == Departures::Contract.digest(expected)

      raise 'Approval did not freeze exact reviewed choices, actor and timestamp'
    end

    def verify_queued(operations)
      jobs = GoodJob::Job.where(job_class: 'PublishDepartureValidationJob', queue_name: JobDriver.queue).to_a
      arguments = jobs.map { |job| job.serialized_params.fetch('arguments') }
      expected = DepartureApproval.where(departure_validation_id: operations.map(&:id)).order(:id).pluck(:id).zip
      return if jobs.length == 40 && arguments.sort == expected.sort && jobs.all? { |job| job.performed_at.nil? && job.finished_at.nil? }

      raise 'Expected forty distinct new scalar-ID publication jobs held on this owned phase queue'
    end
  end
end
