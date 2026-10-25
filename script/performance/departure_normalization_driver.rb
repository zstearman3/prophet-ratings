# frozen_string_literal: true

module OffseasonPerformance
  # One terminal job per fresh measured subpath; no source body enters serialized job arguments.
  module DepartureNormalizationDriver
    def self.call(result, scenario)
      job = enqueue(scenario)
      result['worker'] = wait(job.job_id)
      result['normalization'] = read_normalization(scenario.phase)
      verify(result.fetch('normalization'), scenario)
      result.merge('job_arguments' => job.arguments)
    end

    def self.read_normalization(phase)
      JSON.parse(File.read("/benchmark/departure-normalization-#{phase}.json"))
    end

    def self.enqueue(scenario)
      fixture = scenario.fixture
      return CbbdDepartureNormalizationJob.perform_later(fixture.fetch('season_id')) if scenario.phase == 'cbbd'

      batch = DepartureBatch.find(fixture.fetch('departure_id'))
      LegacyDepartureNormalizationJob.perform_later(batch.attempt.id)
    end

    def self.wait(id)
      deadline = Telemetry.now + 7200
      loop do
        row = JobDriver.poll_job(id, deadline)
        return row if row

        await_worker
      end
    end

    def self.await_worker
      verify_worker
      sleep 0.2
    end

    # A killed worker cannot publish terminal telemetry; do not wait the long corpus timeout after its sampler stops.
    def self.verify_worker(retries = 4)
      return if Time.current - File.mtime('/benchmark/worker-current.json') <= 60

      raise 'Worker sampler stale or worker stopped during departure normalization'
    rescue Errno::ENOENT
      raise if retries.zero?

      sleep 0.05
      verify_worker(retries - 1)
    end

    def self.verify_legacy(normalization, fixture)
      expected = fixture.fetch('dataset_digest')
      raise 'Original corpus digest changed' unless normalization.fetch('dataset_revision') == expected

      verify_cardinalities(normalization, fixture.fetch('cardinalities'))
    end

    def self.verify_cardinalities(normalization, counts)
      raise 'Original corpus not processed' unless normalization.fetch('source_count') == counts.fetch('school_capture_observations') + 1
      return if normalization.fetch('player_observations') == counts.fetch('player_observations')

      raise 'Original player observations not processed'
    end

    def self.verify_cbbd(normalization)
      raise 'Incomplete CBBD teams' unless normalization.fetch('summary').fetch('production') == Content::TEAMS

      attempt = DepartureAcquisition.find(normalization.fetch('attempt_id'))
      Departures::RetainedEvidence.new(attempt).with_paths({}) do |paths|
        replay = Departures::AnnualDataset.new(manifest: attempt.manifest, directory: paths.fetch(:capture_dir)).call
        raise 'CBBD file replay digest changed' unless replay.fetch('dataset_revision') == normalization.fetch('dataset_revision')
      end
    end

    def self.verify(normalization, scenario)
      raise 'Departure normalization did not complete' unless normalization.fetch('status') == 'completed'

      if scenario.phase == 'legacy'
        verify_legacy(normalization, scenario.fixture)
      else
        verify_cbbd(normalization)
      end
    end
  end
end
