# frozen_string_literal: true

require_relative 'telemetry'

module OffseasonPerformance
  # The measured worker consumes the exact original Content corpus, retaining all observations.
  class LegacyDepartureNormalizationJob < HeavyJob
    CLONE_SQL = <<~SQL.squish.freeze
      INSERT INTO departure_acquisitions (departure_batch_id, manifest, plan, status, created_at, updated_at)
      SELECT departure_batch_id, manifest, manifest - 'sources', 'running', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM departure_acquisitions WHERE id = $1
      RETURNING id
    SQL

    def perform(original_id)
      Telemetry.stage('clone_begin')
      attempt = self.class.attempt(original_id)
      Telemetry.stage('clone_complete')
      normalize(attempt)
    end

    def normalize(attempt)
      LegacyDepartureSources.new(attempt).call
      Telemetry.stage('captures_complete')
      record = Departures::StoredDataset.new(attempt).call
      Telemetry.stage('dataset_complete')
      self.class.finish(attempt, record)
    end

    def self.finish(attempt, record)
      attempt.update!(dataset: Departures::StoredDataset.reference(record), status: 'completed', finished_at: Time.current)
      Telemetry.stage('checkpoint_complete')
      DepartureNormalizationResult.new(attempt, record).write('legacy')
    end

    def self.attempt(id)
      bind = ActiveRecord::Relation::QueryAttribute.new('original_id', id, DepartureAcquisition.type_for_attribute('id'))
      result = DepartureAcquisition.connection.exec_query(CLONE_SQL, 'Clone benchmark departure manifest', [bind])
      raise ActiveRecord::RecordNotFound, 'Missing original benchmark departure acquisition' if result.empty?

      DepartureAcquisition.find(result.first.fetch('id'))
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
