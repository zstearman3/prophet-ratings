# frozen_string_literal: true

module Departures
  # Captures incrementally, retaining failed response bytes as well as successful evidence.
  class BatchAcquisition
    MAX_UPLOAD = 5 * 1024 * 1024

    def initialize(attempt)
      @attempt = attempt
      @batch = attempt.departure_batch
    end

    def call
      return unless claim

      capture_sources
      finish
    rescue StandardError => error
      fail_attempt(error.message)
    end

    def recover(attributes)
      batch.with_lock do
        validate_recovery
        successor = recovery_attempt(attributes)
        batch.update!(decisions: [], acknowledgement: {})
        successor
      end
    end

    def finish
      attempt.with_lock do
        require_running
        attempt.update!(**RetainedEvidence.new(attempt).acquisition_result, finished_at: Time.current)
      end
    end

    def self.result_status(dataset)
      complete = dataset.fetch('failures').empty? &&
                 picks_complete?(dataset.fetch('selections').pluck('overall_pick'), dataset.fetch('expected_picks'))
      complete ? 'completed' : 'incomplete'
    end

    def self.picks_complete?(actual, expected)
      actual.sort == expected.sort
    end

    private

    attr_reader :attempt, :batch

    def claim
      attempt.with_lock do
        next false unless attempt.status == 'queued'

        Contract.check!(attempt.plan['provider'] == 'cbbd', 'Legacy HTML acquisition is read-only; create a CBBD successor')
        start
        true
      end
    end

    def validate_recovery
      Contract.check!(!attempt.plan.key?('provider'), 'CBBD recovery requires a new bounded acquisition; JSON upload is not supported')
      attempt.reload
      batch.require_editable
      Contract.check!(attempt.id == batch.attempt.id, 'Recover the latest attempt')
    end

    def start
      plan = attempt.plan
      pending = plan.fetch('sources').map { |source| source.merge('failure' => 'Not acquired; interrupted before this source') }
      attempt.update!(status: 'running', started_at: Time.current, manifest: plan.merge('sources' => pending))
    end

    def fail_attempt(message)
      attempt.with_lock do
        attempt.update!(status: 'failed', failure: message, finished_at: Time.current) unless attempt.terminal?
      end
    end

    def capture_sources
      Dir.mktmpdir('departure-capture-') do |directory|
        CbbdAcquisition.new(plan: attempt.plan, directory:, metadata_only: true, checkpoint: capture_checkpoint(directory)).call
      end
    end

    def capture_checkpoint(directory)
      ->(manifest) { retain_manifest(manifest, directory) }
    end

    def retain_manifest(manifest, directory)
      attempt.with_lock do
        require_running
        attempt.update!(manifest:, evidence: CaptureStore.new(attempt).retain(manifest, directory))
      end
    end

    public_class_method def self.retained_bytes(manifest, directory, evidence)
      RetainedEvidence.sources(manifest).each_with_object(evidence) do |source, retained|
        retained.merge!(capture_bytes(source, directory)) unless retained.key?(source.fetch('id'))
      end
    end

    def require_running
      Contract.check!(attempt.status == 'running', 'Acquisition closed; checkpoint rejected')
    end

    public_class_method def self.capture_bytes(source, directory)
      location = source['snapshot_location']
      return {} unless location

      { source.fetch('id') => { 'snapshot_base64' => Base64.strict_encode64(File.binread(File.join(directory, location))) } }
    end

    def recovery_attempt(attributes)
      successor = batch.acquisitions.create!(recovery_attributes(attributes))
      self.class.new(successor).finish
      successor
    end

    def recovery_attributes(attributes)
      id = attributes.fetch('source_id')
      replacement, evidence = UploadedSource.new(RetainedEvidence.new(attempt).source(id), attributes).call
      { plan: attempt.plan, manifest: replacement_manifest(id, replacement), evidence: attempt.evidence.merge(id => evidence),
        predecessor: attempt, status: 'running', started_at: Time.current }
    end

    def replacement_manifest(id, replacement)
      manifest = attempt.manifest
      manifest.merge('sources' => self.class.replace_source(manifest.fetch('sources'), id, replacement))
    end

    public_class_method def self.replace_source(sources, id, replacement)
      sources.index_by { |source| source.fetch('id') }.merge(id => replacement).values
    end
  end
end
