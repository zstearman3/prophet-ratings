# frozen_string_literal: true

module Departures
  # A JSON source must match its server-generated request and immutable content address.
  class CbbdSnapshot
    def initialize(source:, directory:, settings:)
      @source = source
      @directory = directory
      @expected = CbbdDataset.sources(settings).find { |entry| entry['id'] == source['id'] }
    end

    def call
      validate_request
      parse_capture
    rescue ArgumentError, KeyError, JSON::ParserError, Errno::ENOENT => error
      source.merge('failure' => error.message)
    end

    def validate_metadata
      validate_request
      validate_capture
    end

    def parse_capture
      bytes = saved_bytes if source['snapshot_location']
      source['failure'] ? source : success(bytes)
    end

    def success(bytes)
      validate_capture
      source.merge('rows' => self.class.parse(bytes))
    end

    def self.validate_ledger(capture, requests, directory)
      Contract.check!(capture.fetch('snapshot_kind') == 'raw_json' && requests.include?(capture.fetch('request')),
                      'Invalid capture ledger request/kind')
      read(capture, directory)
    end

    def self.parse(bytes)
      rows = JSON.parse(bytes)
      Contract.check!(Ingestion::Cbbd::Response.valid_rows?(rows), 'Invalid CBBD response envelope')
      rows
    end

    def self.read(source, directory)
      location = source.fetch('snapshot_location')
      sha = source.fetch('snapshot_sha256')
      validate_location(location, sha)
      bytes = File.binread(File.join(directory, location))
      verify_hash(bytes, sha)
    end

    def self.verify_hash(bytes, sha)
      Contract.check!(Digest::SHA256.hexdigest(bytes) == sha, 'JSON snapshot hash mismatch')
      bytes
    end

    def self.validate_location(location, sha)
      Contract.check!(sha.match?(/\A[a-f0-9]{64}\z/) && location == "#{sha}.json", 'Invalid JSON snapshot location')
    end

    private

    attr_reader :source, :directory, :expected

    def validate_request
      Contract.check!(expected.present? && source.slice('id', 'type', 'url', 'request') == expected, 'Invalid CBBD source request')
    end

    def saved_bytes
      self.class.read(source, directory)
    end

    def validate_as_of
      as_of = source['source_as_of']
      Contract.text!(source.fetch('source_as_of_reason'), 'unknown publication timestamp reason') unless as_of
      Time.iso8601(as_of) if as_of
    end

    def validate_capture
      Contract.check!(source.fetch('snapshot_kind') == 'raw_json' && source.fetch('http_status') == 200, 'Unusable JSON capture')
      %w[captured_at observed_at].each { |key| Time.iso8601(source.fetch(key)) }
      validate_as_of
      Contract.check!([true, false].include?(source.fetch('sanitized')), 'Missing response redaction status')
    end
  end
end
