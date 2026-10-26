# frozen_string_literal: true

module Ingestion
  module Cbbd
    # Acquire durably before entering canonical date transactions. Never renew a phase budget.
    class ScheduledSync
      def initialize(run, **options)
        @run = run
        @options = options
        @phase = nil
        @dates = []
      end

      def call
        GoodJob::Job.advisory_lock_key("cbbd-sync:#{@run.id}") do
          @run.reload
          %i[past future].each { |phase| sync_phase(phase) }
        end
        @run
      end

      private

      def sync_phase(phase)
        @phase = phase
        return unless @run.public_send("#{@phase}_status") == 'pending'

        execute_phase
      rescue StandardError => error
        record_phase('failed', error_class: error.class.name)
      end

      def execute_phase
        prepare_dates
        return record_phase('empty') if @dates.empty?
        return record_phase('stale') unless @run.current_authorization?

        record_import(import(acquire))
      end

      def prepare_dates
        @dates = @run.public_send("#{@phase}_dates")
      end

      def acquire
        acquisition = prepare_acquisition
        ReviewAcquisition.new(acquisition, **@options).call
        acquisition.reload
      end

      def record_import(report)
        record_phase(report[:complete] ? 'completed' : 'failed', report)
      end

      def record_phase(status, report = {})
        Rails.logger.info("CBBD sync run=#{@run.id} phase=#{@phase} status=#{status}")
        @run.update!("#{@phase}_status" => status, "#{@phase}_report" => report)
      end

      def prepare_acquisition
        @run.public_send("#{@phase}_acquisition") || @run.transaction { create_acquisition }
      end

      def create_acquisition
        acquisition = CbbdReviewRun.create!(season: @run.season, start_date: @dates.first, end_date: @dates.last,
                                            maximum_requests: @run.maximum_requests, retries: @run.retries)
        @run.update!("#{@phase}_acquisition" => acquisition)
        acquisition
      end

      def import(acquisition)
        options = { season: @run.season, provider: 'cbbd', provider_options: { prepared_run: acquisition } }
        if @phase == :past
          GameSyncRun.new(**options, dates: @dates, resume: false).call
        else
          FutureScheduleRefresh.new(**options, start_date: @dates.first, end_date: @dates.last).call
        end
      end
    end
  end
end
