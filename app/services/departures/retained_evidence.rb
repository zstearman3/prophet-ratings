# frozen_string_literal: true

require 'base64'
require 'tmpdir'

module Departures
  # Replays private database bytes through the unchanged file contracts in a temporary directory.
  class RetainedEvidence
    def initialize(attempt)
      @attempt = attempt
    end

    def dataset
      materialize { |directory| AnnualDataset.new(manifest: attempt.manifest, directory:).call }
    end

    def verified_dataset(plan)
      saved = retained_dataset
      Contract.check!(attempt.plan == plan, 'Preparation changed; request a new acquisition')
      replay = dataset
      Contract.check!(replay == saved, 'Retained departure dataset differs from replay')
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
      original = Base64.strict_decode64(attempt.evidence.fetch(source_id).fetch('snapshot_base64'))
      self.class.validate_bytes(source, original)
      original
    end

    def self.sources(manifest)
      manifest.fetch('sources') + manifest.fetch('captures', [])
    end

    def self.validate_bytes(source, original)
      sha = source.fetch('snapshot_sha256')
      OffseasonInputs::DepartureBundle.validate_location(source.fetch('snapshot_location'), sha)
      Contract.check!(Digest::SHA256.hexdigest(original) == sha, 'Retained source hash mismatch')
    end

    def source(id)
      source = self.class.sources(attempt.manifest).find { |entry| entry.fetch('id') == id }
      Contract.check!(source.present?, 'Unknown retained source')
      source
    end

    private

    attr_reader :attempt

    def retained_dataset
      saved = attempt.dataset
      Contract.check!(attempt.terminal? && saved.present?, 'Acquire usable evidence before reviewing decisions')
      saved
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
