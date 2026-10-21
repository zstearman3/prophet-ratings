# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'securerandom'

module Ingestion
  module Cbbd
    # Immutable private evidence survives retries and process restarts.
    class CaptureStore
      # A replay cannot trust altered capture bytes.
      class IntegrityError < StandardError; end

      attr_reader :directory

      def initialize(directory)
        raise ArgumentError, 'capture_directory is required' if directory.to_s.strip.empty?

        @directory = File.expand_path(directory)
        FileUtils.mkdir_p(@directory, mode: 0o700)
        File.chmod(0o700, @directory)
      end

      def capture(body:, metadata:)
        id = SecureRandom.uuid
        reference = metadata.merge('id' => id, 'sha256' => Digest::SHA256.hexdigest(body),
                                   'bytes' => body.bytesize, 'body_file' => "#{id}.body")
        write("#{id}.body", body)
        write("#{id}.json", JSON.pretty_generate(reference))
        reference
      end

      def manifest(result)
        name = "run-#{SecureRandom.uuid}.json"
        write(name, JSON.pretty_generate(result))
        File.join(directory, name)
      end

      def read(reference)
        name = reference.fetch('body_file')
        raise IntegrityError, 'invalid capture path' unless File.basename(name) == name

        bytes = File.binread(File.join(directory, name))
        raise IntegrityError, 'capture digest mismatch' unless Digest::SHA256.hexdigest(bytes) == reference.fetch('sha256')

        bytes
      end

      private

      def write(name, bytes)
        File.open(File.join(directory, name), File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.binmode.tap { |output| output.write(bytes) }.fsync
        end
      end
    end
  end
end
