# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'tmpdir'

module Recruiting
  # Content-addressed bundles never overwrite previously prepared evidence.
  class Dataset
    attr_reader :extract, :manifest

    def initialize(extract_bytes, snapshot_bytes)
      @extract_bytes = extract_bytes
      @snapshot_bytes = snapshot_bytes
      @extract = Extract.new(extract_bytes)
      @manifest = build_manifest
    end

    def self.load(path)
      dataset = new(File.binread(File.join(path, 'original.json')), File.binread(File.join(path, 'snapshot')))
      expected = File.binread(File.join(path, 'dataset.json'))
      raise ArgumentError, 'Dataset integrity failure; prepare a new bundle' unless expected == dataset.json

      dataset
    end

    def save(root)
      FileUtils.mkdir_p(root)
      destination = File.join(root, manifest.fetch('dataset_revision'))
      return verify_existing(destination) if File.exist?(destination)

      write_bundle(root, destination)
      destination
    end

    def write_bundle(root, destination)
      temporary = Dir.mktmpdir('.recruiting-', root)
      write_files(temporary)
      File.rename(temporary, destination)
    ensure
      FileUtils.rm_rf(temporary) if temporary
    end

    def write_files(directory)
      File.binwrite(File.join(directory, 'original.json'), @extract_bytes)
      File.binwrite(File.join(directory, 'snapshot'), @snapshot_bytes)
      File.binwrite(File.join(directory, 'dataset.json'), json)
    end

    def json
      "#{JSON.pretty_generate(manifest)}\n"
    end

    private

    def verify_existing(destination)
      existing = self.class.load(destination)
      raise ArgumentError, 'Dataset revision conflict' unless existing.json == json

      destination
    end

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
