# frozen_string_literal: true

module OffseasonPerformance
  # Counts persisted logical job outputs using SQL scalars rather than loading annual artifacts into Ruby.
  module JobOutput
    def self.bytes(job)
      name = job.class.name
      if name == 'PrepareDepartureValidationJob'
        return DepartureValidation.where(id: job.arguments.first).pick(Arel.sql('octet_length(report::text)'))
      end

      if name == 'PublishDepartureValidationJob'
        operation = DepartureApproval.find(job.arguments.first).departure_validation
        return OffseasonInputRevision.where(id: operation.offseason_input_revision_id).pick(Arel.sql('octet_length(payload::text)'))
      end
      return normalization_bytes(name) if name.end_with?('DepartureNormalizationJob')
      return File.size('/benchmark/solver.json') if name == 'OffseasonPerformance::SolverJob'

      return File.size("/benchmark/mixed-#{job.job_id}.json") if name.start_with?('OffseasonPerformance::Mixed')

      persisted_bytes(name, job.arguments.first)
    end

    def self.normalization_bytes(name)
      phase = name.include?('Legacy') ? 'legacy' : 'cbbd'
      File.size("/benchmark/departure-normalization-#{phase}.json")
    end

    def self.persisted_bytes(name, id)
      return comparison_bytes(id) if name == 'CompareCbbdReviewJob'

      model, expression = output_query(name)
      model.where(id: Integer(id)).pick(Arel.sql(expression))
    end

    def self.comparison_bytes(id)
      CbbdReviewComparison.where(cbbd_review_run_id: id).order(id: :desc)
                          .pick(Arel.sql('octet_length(report::text) + octet_length(replay::text)'))
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
      return 'normalization terminal accounting JSON file bytes' if job.class.name.end_with?('DepartureNormalizationJob')

      solver = job.instance_of?(OffseasonPerformance::SolverJob)
      solver ? 'solver result JSON file bytes' : 'persisted terminal report/result JSONB text bytes; includes scalar SQL counting cost'
    end
  end
end
