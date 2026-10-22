# frozen_string_literal: true

require 'tempfile'

module Departures
  # Replace a mutable CLI checkpoint only after complete private sibling bytes reach disk.
  class FileCheckpoint
    def initialize(path)
      @path = path
    end

    def call(manifest)
      directory = File.dirname(path)
      Tempfile.create(['.departure-checkpoint-', '.json'], directory) do |file|
        self.class.write(file, manifest)
        File.rename(file.path, path)
        File.open(directory, File::RDONLY, &:fsync)
      end
    end

    def self.write(file, manifest)
      file.binmode
      file.write(JSON.pretty_generate(manifest))
      file.flush
      file.fsync
    end

    private

    attr_reader :path
  end
end
