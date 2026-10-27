# frozen_string_literal: true

module Recruiting
  # Uses the bounded CBBD client and saves captures plus normalized rows atomically.
  class BatchAcquisition
    def initialize(batch)
      @batch = batch
    end

    def call
      return if batch.reload.status.in?(%w[ready published failed])

      raise 'Acquisition interrupted; explicitly fetch a new batch. Retained evidence is unchanged.' if batch.status == 'fetching'

      acquire
    rescue StandardError => error
      record_failure(error)
    end

    private

    attr_reader :batch

    def record_failure(error)
      message = error.message
      batch.update!(status: 'failed', failure_message: message)
      Rails.logger.error("Recruiting batch #{batch.id} failed: #{error.class}: #{message}")
    rescue StandardError
      raise error
    end

    def acquire
      batch.update!(status: 'fetching')
      raise ArgumentError, 'Live 247 acquisition is retired; explicitly fetch a new CBBD batch.' unless batch.cbbd?

      CbbdAcquisition.new(batch).call { store_rows }
    end

    def store_rows
      report = Preview.new(batch.dataset, batch.season).call
      report.fetch('rows').each { |row| batch.entries.create!(RecruitingEntry.source_attributes(row)) }
    end
  end
end
