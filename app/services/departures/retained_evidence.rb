# frozen_string_literal: true

require 'base64'
require 'tmpdir'

module Departures
  # Replays private database bytes through the unchanged file contracts in a temporary directory.
  class RetainedEvidence
    def self.new(attempt, **options)
      return super unless self == RetainedEvidence

      version = storage_version(attempt, options)
      return super unless version

      stored_reader(attempt, version, options)
    end

    def self.stored_reader(attempt, version, options)
      Contract.check!(version == CaptureStore::VERSION, 'Unsupported departure capture storage version')
      stored = attempt.has_attribute?(:evidence) && attempt.has_attribute?(:dataset) ? attempt : DepartureAcquisition.find(attempt.id)
      StoredEvidence.new(stored, **options)
    end

    def self.storage_version(attempt, options)
      return attempt.evidence['storage_version'] unless options[:comparison] == :persisted || !attempt.has_attribute?(:evidence)

      DepartureAcquisition.where(id: attempt.id).pick(Arel.sql("evidence->>'storage_version'"))
    end

    def initialize(attempt, comparison: :memory)
      @attempt = attempt
      @comparison = comparison
    end

    def dataset
      materialize { |directory| AnnualDataset.new(manifest: attempt.manifest, directory:).call }
    end

    def captured_sources
      materialize { |directory| CapturedSources.new(attempt, directory).call }
    end

    def acquisition_result
      return reviewed_result unless CapturePreparation.capture_only?(attempt.plan)

      complete = captured_sources.none? { |source| source['failure'] }
      { dataset: {}, status: complete ? 'completed' : 'incomplete' }
    end

    def verified_dataset(plan)
      matches = dataset_comparison
      Contract.check!(attempt.plan == plan, 'Preparation changed; request a new acquisition')
      replay = dataset
      Contract.check!(matches.call(replay), 'Retained departure dataset differs from replay')
      replay
    end

    def publish(review, season)
      publication = yield bundle(review, season)
      with_paths(review) { |paths| OffseasonInputs::Import.new(season:, kind: 'departures', paths:, publication:).apply_preview }
    end

    def bundle(review, season)
      with_paths(review) { |paths| OffseasonInputs::DepartureBundle.new(paths, season).call }
    end

    def with_paths(review)
      materialize do |directory|
        paths = self.class.paths(directory)
        Contract.write(paths.fetch(:dataset_path), attempt.dataset)
        Contract.write(paths.fetch(:review_path), review)
        yield paths
      end
    end

    def self.paths(directory)
      { capture_dir: directory, dataset_path: File.join(directory, 'dataset.json'), review_path: File.join(directory, 'review.json') }
    end

    def filename(id)
      extension = source(id).fetch('snapshot_kind') == 'raw_json' ? 'json' : 'html'
      "departure-source-#{attempt.id}.#{extension}"
    end

    def bytes(source_id)
      source = source(source_id)
      encoded = if @comparison == :persisted
                  RetainedEvidence.persisted_source(attempt.id, source_id)
                else
                  attempt.evidence.fetch(source_id).fetch('snapshot_base64')
                end
      self.class.validate_bytes(source, Base64.strict_decode64(encoded))
    end

    def self.sources(manifest)
      manifest.fetch('sources') + manifest.fetch('captures', [])
    end

    def self.validate_bytes(source, original)
      sha = source.fetch('snapshot_sha256')
      OffseasonInputs::DepartureBundle.validate_location(source.fetch('snapshot_location'), sha)
      Contract.check!(Digest::SHA256.hexdigest(original) == sha, 'Retained source hash mismatch')
      original
    end

    def source(id)
      source = self.class.sources(attempt.manifest).find { |entry| entry.fetch('id') == id }
      Contract.check!(source.present?, 'Unknown retained source')
      source
    end

    private

    attr_reader :attempt

    def reviewed_result
      facts = dataset
      { dataset: facts, status: BatchAcquisition.result_status(facts) }
    end

    def dataset_comparison
      return self.class.persisted_comparison(attempt) if @comparison == :persisted

      saved = attempt.dataset
      Contract.check!(attempt.terminal? && saved.present?, 'Acquire usable evidence before reviewing decisions')
      ->(replay) { replay == saved }
    end

    # Readiness uses a fresh persisted acquisition. Keep its saved JSON in PostgreSQL while fully replaying the raw sources.
    public_class_method def self.persisted_comparison(attempt)
      scope = DepartureAcquisition.where(id: attempt.id)
      Contract.check!(attempt.persisted? && attempt.terminal? &&
                      scope.where("jsonb_typeof(dataset) = 'object'").where.not(dataset: {}).exists?,
                      'Acquire usable evidence before reviewing decisions')
      ->(replay) { DepartureAcquisition.uncached { scope.exists?(dataset: replay) } }
    end

    public_class_method def self.persisted_source(attempt_id, source_id)
      encoded = DepartureAcquisition.uncached do
        DepartureAcquisition.where(id: attempt_id).pick(Arel.sql("jsonb_extract_path_text(evidence, ?, 'snapshot_base64')", source_id))
      end
      Contract.check!(encoded.is_a?(String), 'Missing retained source bytes')
      encoded
    end

    def materialize
      Dir.mktmpdir('departure-evidence-') do |directory|
        write_sources(directory)
        Contract.write(File.join(directory, 'manifest.json'), attempt.manifest)
        yield directory
      end
    end

    def write_sources(directory)
      self.class.sources(attempt.manifest).each do |source|
        location = source['snapshot_location']
        Contract.write_bytes(File.join(directory, location), bytes(source.fetch('id'))) if location
      end
    end
  end
end
