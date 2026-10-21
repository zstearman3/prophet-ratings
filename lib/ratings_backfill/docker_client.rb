# frozen_string_literal: true

require 'open3'

module RatingsBackfill
  # Docker operations are always read-only or scoped to one owned container name.
  class DockerClient
    # Represents unavailable Docker commands and retains their diagnostic message.
    class Failure < StandardError; end

    def verify
      read('info')
    rescue Failure => error
      raise ArgumentError, "Docker is unavailable: #{error.message}"
    end

    def remove(name)
      read('rm', name)
    rescue Failure => error
      warn "[backfill] Completed container retained; docker rm #{name} failed: #{error.message}"
    end

    def memory(name)
      read('stats', '--no-stream', '--format', '{{.MemUsage}} {{.MemPerc}}', name)
    rescue Failure
      'unavailable (container may still be starting)'
    end

    def oom(name)
      read('inspect', '--format', '{{.State.OOMKilled}}', name)
    rescue Failure
      'unknown (container may not have started)'
    end

    def stop(name)
      read('stop', '--time', '10', name)
    rescue Failure => error
      warn "[backfill] Could not stop #{name}: #{error.message}"
    end

    private

    def read(*)
      output, errors, status = Open3.capture3('docker', *)
      raise Failure, errors.strip unless status.success?

      output.strip
    end
  end
end
