# frozen_string_literal: true

module OffseasonPerformance
  # The measured worker consumes the exact original Content corpus, retaining all observations.
  class LegacyDepartureNormalizationJob < HeavyJob
    def perform(original_id)
      attempt = self.class.attempt(original_id)
      LegacyDepartureSources.new(attempt).call
      record = Departures::StoredDataset.new(attempt).call
      attempt.update!(dataset: Departures::StoredDataset.reference(record), status: 'completed', finished_at: Time.current)
      DepartureNormalizationResult.new(attempt, record).write('legacy')
    end

    def self.attempt(id)
      original = DepartureAcquisition.select(:id, :departure_batch_id, :manifest).find(id)
      attributes = original.attributes.slice('departure_batch_id', 'manifest')
                           .merge('plan' => original.manifest.except('sources'), 'status' => 'running')
      DepartureAcquisition.create!(attributes)
    end
  end

  # Separately measures the ordinary five-response source and annual-combination paths.
  class CbbdDepartureNormalizationJob < HeavyJob
    def perform(season_id)
      attempt = self.class.attempt(season_id)
      CbbdDepartureSources.new(attempt).call
      Departures::BatchAcquisition.new(attempt).finish
      record = DepartureDatasetNormalization.find(attempt.dataset.fetch('normalization_id'))
      DepartureNormalizationResult.new(attempt, record).write('cbbd')
    end

    def self.attempt(season_id)
      plan = DepartureCbbdContent.plan
      batch = DepartureBatch.create!(season_id:, plan:)
      batch.acquisitions.create!(plan:, status: 'running', started_at: Time.current)
    end
  end

  # Scalar SQL accounting never expands the full logical annual dataset for telemetry.
  class DepartureNormalizationResult
    def initialize(attempt, record)
      @attempt = attempt
      @record = record
    end

    def write(phase)
      File.write("/benchmark/departure-normalization-#{phase}.json", JSON.generate(call))
    end

    def call
      { 'attempt_id' => @attempt.id, 'status' => @attempt.status, 'dataset_revision' => @record.dataset_revision,
        'summary' => @record.summary, 'source_count' => @record.source_normalization_ids.size,
        'body_count' => captures.count, 'response_bytes' => captures.sum(:byte_size),
        'observation_count' => observations.count, 'normalized_source_rows' => normalized_rows.count,
        'player_observations' => player_observations,
        'dataset_bytes' => @record.rows.sum(Arel.sql('octet_length(fact::text)')),
        'stored_bytes' => ActiveRecord::Base.connection.select_value('SELECT pg_database_size(current_database())').to_i }
    end

    def observations
      DepartureCaptureObservation.where(id: @attempt.evidence.fetch('observations').values)
    end

    def captures
      DepartureSourceCapture.where(id: observations.select(:departure_source_capture_id))
    end

    def normalized_rows
      DepartureNormalizedRow.where(departure_source_normalization_id: @record.source_normalization_ids.values)
    end

    def player_observations
      if @record.header['provider'] == 'cbbd'
        ids = @record.source_normalization_ids.slice('player-regular', 'player-postseason').values
        DepartureNormalizedRow.where(departure_source_normalization_id: ids).count
      else
        normalized_rows.where("json_typeof(fact->'players') = 'array'").sum(Arel.sql("json_array_length(fact->'players')"))
      end
    end
  end
end
