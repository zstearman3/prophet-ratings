# frozen_string_literal: true

module OffseasonPerformance
  # Uses durable GoodJob intervals, not queue names or telemetry alone, to prove coexistence.
  class MixedWorkload
    def initialize(scenario)
      @fixture = scenario.fixture
      @args = []
      @result = {}
    end

    def call(result, &)
      @result = result
      jobs = enqueue
      collect(result, &)
      File.write("/benchmark/mixed-release-#{@args.first}", 'release')
      complete(jobs)
    end

    def enqueue
      @args = [SecureRandom.hex(12), *@fixture.fetch_values('season_id', 'model_id')]
      heavy = Array.new(2) { MixedHeavyJob.perform_later(*@args) }
      await_ready(heavy.first)
      heavy << MixedOrdinaryJob.perform_later(*@args)
    end

    def collect(result)
      %w[warmups samples].zip([10, 30]).each do |key, count|
        count.times do
          result.fetch(key) << yield
          sleep 0.3
        end
      end
    end

    def complete(jobs)
      ids = jobs.map(&:job_id)
      @result['worker_jobs'] = MixedWorkload.wait_jobs(ids)
      @result['executions'] = MixedWorkload.execution_rows(ids)
      @result['solutions'] = MixedWorkload.solutions(ids.first(2))
      @result.fetch('failures').concat(MixedWorkload.validate(@result.fetch('executions'), @result.fetch('samples')))
    end

    def self.wait_jobs(ids)
      ids.map { |id| JobDriver.wait_job(id) }
    end

    def self.execution_rows(ids)
      ids.map { |id| execution(id) }
    end

    def self.solutions(ids)
      ids.map { |id| JSON.parse(File.read("/benchmark/mixed-#{id}.json")) }
    end

    def await_ready(job)
      deadline = MixedWorkload.deadline(180)
      path = "/benchmark/mixed-ready-#{@args.first}.json"
      until File.exist?(path)
        raise 'Mixed heavy readiness timeout' if Telemetry.now > deadline

        sleep 0.1
      end
      raise 'Wrong heavy readiness identity' unless JSON.parse(File.read(path)).fetch('job_id') == job.job_id
    end

    def self.deadline(seconds)
      Telemetry.now + seconds
    end

    def self.execution(id)
      deadline = deadline(10)
      loop do
        evidence = poll_execution(id, deadline)
        return evidence if evidence

        sleep 0.1
      end
    end

    def self.poll_execution(id, deadline)
      evidence = execution_row(id)
      raise 'Missing or duplicate persisted execution evidence' if !evidence && Telemetry.now > deadline

      evidence
    end

    def self.execution_row(id)
      job = GoodJob::Job.find_by!(active_job_id: id)
      rows = GoodJob::Execution.where(active_job_id: id).order(:created_at).to_a
      row = rows.first
      return unless job.finished_at && rows.size == 1 && row.finished_at

      serialize_execution(job, row, id)
    end

    def self.serialize_execution(job, row, id)
      { 'active_job_id' => id, 'created_at' => job.created_at.to_f, 'started_at' => row.created_at.to_f,
        'finished_at' => row.finished_at.to_f, 'process_id' => row.process_id, 'error' => row.error,
        'arguments' => row.serialized_params.fetch('arguments') }
    end

    def self.validate(rows, samples)
      return ['missing persisted execution evidence'] unless valid_rows?(rows)

      execution_failures(rows) + identity_failures(rows) + window_failures(samples, rows.first)
    end

    def self.execution_failures(rows)
      first, second, ordinary = rows
      [('heavy executions overlap' if second.fetch('started_at') < first.fetch('finished_at')),
       ('ordinary start exceeds 10s' if ordinary.fetch('started_at') - ordinary.fetch('created_at') > 10),
       ('ordinary execution does not overlap first heavy' unless overlap?(first, ordinary))].compact
    end

    def self.identity_failures(rows)
      [('job operation identity mismatch' unless rows.pluck('arguments').uniq.size == 1),
       ('worker process identity mismatch' unless rows.pluck('process_id').uniq.size == 1)].compact
    end

    def self.window_failures(samples, first)
      samples.all? { |sample| inside?(sample, first) } ? [] : ['HTTP samples outside first heavy execution']
    end

    def self.valid_rows?(rows)
      rows.size == 3 && rows.pluck('error').compact.empty? && rows.all? { |row| valid_row?(row) }
    end

    def self.valid_row?(row)
      arguments = row['arguments']
      valid_times?(row) && row['started_at'] < row['finished_at'] && row['process_id'].present? &&
        row['active_job_id'].present? && arguments.is_a?(Array) && arguments.size == 3
    end

    def self.valid_times?(row)
      row.values_at('created_at', 'started_at', 'finished_at').all? { |value| value.is_a?(Numeric) && value.finite? }
    end

    def self.overlap?(first, ordinary)
      ordinary.fetch('started_at') < first.fetch('finished_at') && ordinary.fetch('finished_at') > first.fetch('started_at')
    end

    def self.inside?(sample, first)
      started, finished = sample.values_at('started_at', 'finished_at')
      started.is_a?(Numeric) && finished.is_a?(Numeric) && started >= first.fetch('started_at') && finished <= first.fetch('finished_at')
    end
  end
end
