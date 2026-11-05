# frozen_string_literal: true

module Ingestion
  module Cbbd
    # The provider commits games first; the day checkpoint must not enclose their transactions.
    class RefreshDay
      def initialize(provider:, date:, on_day:)
        @provider = provider
        @date = date
        @on_day = on_day
      end

      def call
        result = @provider.call(@date).merge(date: @date)
        outcome = result[:complete] ? result : self.class.held_report(result)
        @on_day&.call(outcome)
        outcome
      end

      def self.held_report(result)
        result.merge(error: 'Some source games need admin review.', status: 'completed_with_issues',
                     rejection_observation_ids: HistoricalSyncDay.rejection_ids(result))
      end
    end
  end
end
