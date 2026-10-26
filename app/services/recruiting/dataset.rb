# frozen_string_literal: true

require 'digest'

module Recruiting
  # Normalizes retained database captures and fingerprints their original bytes.
  class Dataset
    attr_reader :extract, :manifest

    def initialize(extract_bytes, snapshot_bytes)
      @extract_bytes = extract_bytes
      @snapshot_bytes = snapshot_bytes
      @extract = self.class.parse_extract(extract_bytes)
      @extract.verify_snapshot(snapshot_bytes) if @extract.is_a?(CbbdExtract)
      @manifest = build_manifest
    end

    def self.parse_extract(bytes)
      text = bytes.dup.force_encoding(Encoding::UTF_8)
      raise ArgumentError, 'Extract must be valid UTF-8' unless text.valid_encoding?

      document = JSON.parse(text)
      parser(document).new(bytes)
    end

    def self.parser(document)
      document.is_a?(Hash) && document['extraction_version'] == CbbdExtract::VERSION ? CbbdExtract : Extract
    end

    private

    def build_manifest
      extract_hash = Digest::SHA256.hexdigest(@extract_bytes)
      snapshot_hash = Digest::SHA256.hexdigest(@snapshot_bytes)
      {
        'contract_version' => 1, 'dataset_revision' => Digest::SHA256.hexdigest("#{extract_hash}:#{snapshot_hash}"),
        'extract_sha256' => extract_hash, 'snapshot_sha256' => snapshot_hash,
        'metadata' => extract.metadata, 'rows' => extract.rows
      }
    end
  end
end
