# frozen_string_literal: true

require 'fileutils'

module Departures
  # Makes a single public request and retains exact bytes, including blocked responses.
  class SourceCapture
    def initialize(directory:)
      @directory = directory
    end

    def call(source)
      captured_at = Time.now.utc.iso8601(6)
      response = HTTParty.get(Contract.url!(source.fetch('url')), timeout: 30, follow_redirects: false)
      source.merge(snapshot(response.body.to_s.b), self.class.metadata(captured_at, response.code))
    rescue HTTParty::Error, Timeout::Error, SocketError, SystemCallError, EOFError, OpenSSL::SSL::SSLError, Net::ProtocolError => error
      failed_capture(source, captured_at, error)
    end

    def self.failed(source, captured_at, error)
      source.merge('captured_at' => captured_at, 'observed_at' => captured_at, 'failure' => "Request failed: #{error.class}")
    end

    def self.metadata(captured_at, status)
      { 'captured_at' => captured_at, 'observed_at' => captured_at, 'http_status' => status,
        'source_as_of' => nil, 'source_as_of_reason' => 'Publication timestamp not established',
        'failure' => status == 200 ? nil : "HTTP #{status}; access not bypassed" }
    end

    private

    attr_reader :directory

    def failed_capture(source, captured_at, error)
      self.class.failed(source, captured_at, error)
    end

    def snapshot(bytes)
      sha = Digest::SHA256.hexdigest(bytes)
      FileUtils.mkdir_p(directory)
      Contract.write_bytes(File.join(directory, "#{sha}.html"), bytes)
      { 'snapshot_kind' => 'raw_html', 'snapshot_location' => "#{sha}.html", 'snapshot_sha256' => sha }
    end
  end
end
