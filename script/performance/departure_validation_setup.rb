# frozen_string_literal: true

module OffseasonPerformance
  # Setup cost is disclosed separately from the one real full-source worker measurement.
  class DepartureValidationSetup
    def initialize(fixture)
      @fixture = fixture
      @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @before_bytes = DepartureValidationDriver.database_bytes
      @cloned_bytes = nil
    end

    def call(result)
      operations = VerifiedDepartureReuse.clone_cases(@fixture.fetch('departure_id'), 41)
      @cloned_bytes = DepartureValidationDriver.database_bytes
      source = validate(operations.first, result)
      operations.drop(1).each { |candidate| VerifiedDepartureReuse.new(source).call(candidate) }
      retain_cases(operations)
      result.merge!(summary(source), 'setup' => setup_summary)
    end

    private

    def validate(source, result)
      job = PrepareDepartureValidationJob.perform_later(source.id)
      result['worker'] = DepartureValidationDriver.wait(job.job_id)
      source.reload
      raise "Validation #{source.status}: #{source.error}" unless source.status == 'ready'

      DepartureValidationDriver.verify_proposal(source, normalization(source), @fixture)
      result['job_arguments'] = job.arguments
      source
    end

    def normalization(source)
      DepartureDatasetNormalization.select(:id, :dataset_revision, :summary).find(source.departure_dataset_normalization_id)
    end

    def retain_cases(operations)
      data = { 'original_id' => @fixture.fetch('departure_id'), 'operation_ids' => operations.map(&:id),
               'batch_ids' => operations.map(&:departure_batch_id) }
      File.write('/benchmark/departure-validation-cases.json', JSON.generate(data))
    end

    def summary(source)
      record = normalization(source)
      { 'operation_id' => source.id, 'status' => source.status, 'dataset_revision' => record.dataset_revision,
        'summary' => record.summary, 'proposals' => source.proposals.count }
    end

    def setup_summary
      { 'raw_validations' => 1, 'verified_reuses' => 40, 'distinct_cases' => 41,
        'clone_db_bytes' => @cloned_bytes - @before_bytes,
        'total_setup_db_bytes' => DepartureValidationDriver.database_bytes - @before_bytes,
        'setup_elapsed_seconds' => Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started }
    end
  end
end
