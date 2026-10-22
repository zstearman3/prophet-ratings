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
      return if attempt.reload.terminal?
      return fail_attempt('Interrupted acquisition; start a new attempt.') if attempt.status == 'running'

      acquire_sources
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
      dataset = RetainedEvidence.new(attempt).dataset
      attempt.update!(dataset:, status: self.class.result_status(dataset), finished_at: Time.current)
    end

    def self.result_status(dataset)
      complete = dataset.fetch('failures').empty? &&
                 dataset.fetch('selections').pluck('overall_pick').sort == dataset.fetch('expected_picks').sort
      complete ? 'completed' : 'incomplete'
    end

    private

    attr_reader :attempt, :batch

    def acquire_sources
      start
      Dir.mktmpdir('departure-capture-') { |directory| capture_sources(directory) }
      finish
    end

    def validate_recovery
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
      attempt.reload
      attempt.update!(status: 'failed', failure: message, finished_at: Time.current) unless attempt.terminal?
    end

    def capture_sources(directory)
      attempt.plan.fetch('sources').each { |source| capture(source, directory) }
    end

    def capture(source, directory)
      captured = SourceCapture.new(directory:).call(source)
      evidence = attempt.evidence.merge(self.class.capture_bytes(captured, directory))
      attempt.update!(manifest: replacement_manifest(source['id'], captured), evidence:)
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
      replacement, evidence = UploadedSource.new(recovery_source(id), attributes).call
      { plan: attempt.plan, manifest: replacement_manifest(id, replacement), evidence: attempt.evidence.merge(id => evidence),
        predecessor: attempt, status: 'running', started_at: Time.current }
    end

    def recovery_source(id)
      source = attempt.manifest.fetch('sources').find { |entry| entry['id'] == id }
      Contract.check!(source.present?, 'Unknown recovery source')
      source
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
