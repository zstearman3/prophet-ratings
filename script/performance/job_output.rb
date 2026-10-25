# frozen_string_literal: true

module OffseasonPerformance
  # Counts persisted logical job outputs using SQL scalars rather than loading annual artifacts into Ruby.
  module JobOutput
    def self.bytes(job)
      name = job.class.name
      return File.size('/benchmark/solver.json') if name == 'OffseasonPerformance::SolverJob'

      model, expression = output_query(name)
      model.where(id: Integer(job.arguments.first)).pick(Arel.sql(expression))
    end

    def self.output_query(name)
      case name
      when 'PreviewPreseasonJob', 'PublishPreseasonJob'
        [PreseasonPublication, 'octet_length(report::text) + octet_length(result::text)']
      when 'RefreshScheduleJob'
        [ScheduleRefreshRun, 'octet_length(report::text)']
      else
        raise KeyError, "Unknown benchmark job: #{name}"
      end
    end

    def self.definition(job)
      solver = job.instance_of?(OffseasonPerformance::SolverJob)
      solver ? 'solver result JSON file bytes' : 'persisted terminal report/result JSONB text bytes; includes scalar SQL counting cost'
    end
  end
end
