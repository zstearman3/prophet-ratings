# frozen_string_literal: true

module OffseasonPerformance
  # Verifies persisted synthetic cardinalities and records reproducible content provenance.
  class FixtureManifest
    def initialize(state)
      @state = state
    end

    def persisted_counts
      dataset = @state.attempt.dataset
      production = dataset.fetch('production')
      players = production.flat_map { |table| table.fetch('players') }
      @state.content.cardinalities.merge(
        'target_teams' => @state.season.team_seasons.count, 'distinct_school_players' => FixtureManifest.distinct_players(players),
        'draft_picks' => dataset.fetch('selections').size, 'school_capture_observations' => production.size,
        'player_observations' => players.size, 'historical_snapshots' => TeamRatingSnapshot.count,
        'cbbd_game_observations' => CbbdReviewRun.where(id: @state.cbbd.id)
                                                 .pick(Arel.sql("jsonb_array_length(normalized_replay->'observations')"))
      )
    end

    def self.distinct_players(players)
      players.pluck('player_source_url').map { |url| URI(url).path }.uniq.size
    end

    def persisted_bytes
      connection = ActiveRecord::Base.connection
      acquisition = connection.select_one(<<~SQL.squish)
        SELECT octet_length(evidence::text) AS raw_evidence_json,
               octet_length(dataset::text) AS normalized_dataset_json
        FROM departure_acquisitions WHERE id = #{@state.attempt.id}
      SQL
      query = "SELECT octet_length(payload::text) FROM offseason_input_revisions WHERE id = #{@state.departure.id}"
      revision = connection.select_value(query)
      acquisition.merge('published_revision_json' => revision.to_i)
    end

    def self.legacy_prior_digest
      digest = Digest::SHA256.new
      digest.update("offseason-legacy-priors-v1\n")
      PreseasonPrior.select(:id, :team_season_id, :inputs, :outputs).find_each(batch_size: 1) do |row|
        digest.update(Departures::Contract.digest([row.team_season_id, row.inputs, row.outputs])).update("\n")
      end
      digest.hexdigest
    end

    def generated_bytes
      attempt = @state.attempt
      { 'raw_evidence_json' => JSON.generate(attempt.evidence).bytesize,
        'normalized_dataset_json' => JSON.generate(attempt.dataset).bytesize,
        'published_revision_json' => JSON.generate(@state.departure.payload).bytesize,
        'legacy_prior_inputs_json' => PreseasonPrior.sum(Arel.sql('octet_length(inputs::text)')) }
    end

    def call(publication)
      counts = persisted_counts
      verify_counts(counts)
      record_metadata(publication).merge('version' => 1, 'scale' => @state.content.scale, 'cardinalities' => counts).merge(measurements)
    end

    def verify_counts(counts)
      expected = @state.content.cardinalities
      matches = expected.all? { |key, value| counts[key] == value }
      raise 'Incomplete persisted synthetic fixture' unless matches
    end

    def record_metadata(publication)
      cbbd = @state.cbbd
      { 'dataset_digest' => @state.attempt.dataset.fetch('dataset_revision'), 'season_id' => @state.season.id,
        'publication_id' => publication.id, 'departure_id' => @state.batch.id, 'cbbd_id' => cbbd.id,
        'schedule_season_id' => cbbd.season_id, 'schedule_date' => '2024-11-01', 'model_id' => @state.model.id }
    end

    def measurements
      { 'bytes' => generated_bytes, 'model' => FixtureManifest.model_metadata(@state.model.config), 'persisted_bytes' => persisted_bytes,
        'legacy_prior_digest' => FixtureManifest.legacy_prior_digest,
        'legacy_prior_digest_algorithm' => 'SHA256(header + ordered canonical row SHA256 plus newline); header=offseason-legacy-priors-v1',
        'cbbd_artifacts' => cbbd_artifacts, 'runtime' => FixtureManifest.runtime,
        'postgres_bytes' => ActiveRecord::Base.connection.select_value('SELECT pg_database_size(current_database())').to_i }
    end

    def cbbd_artifacts
      connection = ActiveRecord::Base.connection
      connection.select_one(<<~SQL.squish)
        SELECT run.evidence_digest, comparison.artifact_digest,
               octet_length(run.normalized_replay::text) AS normalized_replay_bytes,
               octet_length(comparison.report::text) AS report_bytes,
               octet_length(comparison.replay::text) AS replay_bytes
        FROM cbbd_review_runs run
        JOIN cbbd_review_comparisons comparison ON comparison.id = run.active_comparison_id
        WHERE run.id = #{@state.cbbd.id}
      SQL
    end

    def self.runtime
      config = Rails.application.config
      { 'rails' => Rails.version, 'good_job' => GoodJob::VERSION,
        'postgresql' => ActiveRecord::Base.connection.select_value('SHOW server_version'),
        'eager_load' => config.eager_load, 'server_timing' => config.server_timing }
    end

    def self.model_metadata(config)
      preseason = config.fetch('preseason')
      { 'bundle_version' => config.fetch('bundle_name'), 'config_sha256' => Departures::Contract.digest(config),
        'coaching_adjustment' => preseason.key?('coaching'), 'reviewed_efficiency_adjustment' => preseason.key?('efficiency_adjustment') }
    end
  end
end
