# frozen_string_literal: true

module OffseasonPerformance
  # Collects garbage only in disposable fixture processes and records setup progress/cost separately.
  module SetupPhase
    def self.call(name)
      started = collect_time
      record(Telemetry.memory.merge('phase' => name, 'state' => 'begin'))
      result = yield
      complete(name, started)
      result
    end

    def self.collect_time
      GC.start
      Telemetry.now
    end

    def self.complete(name, started)
      GC.start
      record(Telemetry.memory.merge('phase' => name, 'elapsed' => Telemetry.now - started))
    end

    def self.record(metrics)
      File.open('/benchmark/setup-progress.jsonl', 'a') { |file| file.puts(JSON.generate(metrics)) }
    end
  end
end
