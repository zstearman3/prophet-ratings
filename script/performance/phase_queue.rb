# frozen_string_literal: true

module OffseasonPerformance
  # Keeps interrupted phase jobs retained while later workers select only their own queue.
  module PhaseQueue
    def self.prefix(owner, phase)
      raise ArgumentError, 'Invalid benchmark queue owner' unless owner&.match?(/\Aoffseason-[a-f0-9]+\z/)
      raise ArgumentError, 'Invalid benchmark queue phase' unless phase&.match?(/\A[a-z]+(?:-[a-z]+)*\z/)

      "#{owner}_#{phase}"
    end

    def self.name(owner, phase)
      "#{prefix(owner, phase)}_default"
    end

    def self.worker_arguments(owner, phase)
      ['start', '--max-threads=1', "--queues=#{name(owner, phase)}"]
    end
  end
end
