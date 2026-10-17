# frozen_string_literal: true

require 'digest'

module Recruiting
  # Normalizes retained database captures and fingerprints their original bytes.
  class Dataset
    attr_reader :extract, :manifest

    def initialize(extract_bytes, snapshot_bytes)
      @extract_bytes = extract_bytes
      @snapshot_bytes = snapshot_bytes
      @extract = Extract.new(extract_bytes)
      @manifest = build_manifest
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
