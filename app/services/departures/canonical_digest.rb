# frozen_string_literal: true

require 'digest'
require 'json'

module Departures
  # Streams the same sorted JSON bytes without copying the entire evidence tree.
  class CanonicalDigest
    def initialize
      @digest = Digest::SHA256.new
    end

    def call(value)
      JSON::State.new(sort_keys: true).generate(value, self)
      @digest.hexdigest
    end

    def flush
      self
    end

    def write(bytes)
      @digest.update(bytes)
      bytes.bytesize
    end
  end
end
