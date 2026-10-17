# frozen_string_literal: true

module Recruiting
  # Uses the existing bounded fetch/parser and saves captures plus normalized rows atomically.
  class BatchAcquisition
    def initialize(batch)
      @batch = batch
    end

    def call
      return if batch.reload.status.in?(%w[ready published failed])

      acquire
    rescue StandardError => error
      batch.update!(status: 'failed', failure_message: error.message)
      raise
    end

    private

    attr_reader :batch

    def acquire
      batch.update!(status: 'fetching')
      retain(Acquisition.new(metadata).fetch(20))
    end

    def metadata
      now = Time.current.iso8601
      { 'source_year' => batch.source_year, 'target_season' => batch.season.year, 'category' => Extract::CATEGORY,
        'observed_at' => now, 'retrieved_at' => now, 'captured_at' => now }
    end

    def retain(source)
      artifact = AcquisitionArtifact.new(source)
      attributes = artifact.database_attributes
      batch.with_lock do
        batch.update!(attributes)
        store_rows if batch.status == 'ready'
      end
    end

    def store_rows
      report = Preview.new(batch.dataset, batch.season).call
      report.fetch('rows').each { |row| batch.entries.create!(RecruitingEntry.source_attributes(row)) }
    end
  end
end
