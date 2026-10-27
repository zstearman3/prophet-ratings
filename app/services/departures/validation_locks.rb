# frozen_string_literal: true

module Departures
  # The same order protects content and absent-row identities during sealing and publication.
  module ValidationLocks
    TABLES = %w[seasons teams team_aliases team_external_identities team_seasons team_offseason_profiles
                offseason_input_revisions departure_batches departure_acquisitions departure_source_captures
                departure_capture_observations departure_dataset_normalizations departure_dataset_rows
                departure_validations departure_proposals departure_approvals].freeze

    def self.lock
      connection = ApplicationRecord.connection
      connection.execute("SET LOCAL lock_timeout = '5s'")
      TABLES.each { |table| connection.execute("LOCK TABLE #{connection.quote_table_name(table)} IN SHARE ROW EXCLUSIVE MODE") }
      yield
    end

    def self.web_transaction
      ApplicationRecord.transaction do
        ApplicationRecord.connection.execute("SET LOCAL lock_timeout = '300ms'")
        yield
      end
    rescue ActiveRecord::LockWaitTimeout
      raise ArgumentError, 'Departure worker is busy; retry shortly'
    end
  end
end
