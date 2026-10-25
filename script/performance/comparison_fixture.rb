# frozen_string_literal: true

module OffseasonPerformance
  # Uses the real comparison algorithm; only its canonical fingerprint is streamed during setup.
  class FixtureComparison < Ingestion::Reconciliation::Comparison
    attr_reader :replay

    def fingerprint(games, local)
      ids = (games.flat_map { |row| row['candidate_ids'] } + local.window_games.ids).uniq.sort
      Departures::CanonicalDigest.new.call([VERSION, replay, fingerprint_rows(ids)])
    end
  end

  # Constructs a new synthetic artifact atomically; existing finalized records remain immutable.
  module ComparisonFixture
    COLUMNS = { 'replay' => 'replay', 'report' => 'report' }.freeze
    UPDATES = {
      'report' => 'UPDATE cbbd_review_comparisons SET report = ?::jsonb WHERE id = ?',
      'replay' => 'UPDATE cbbd_review_comparisons SET replay = ?::jsonb WHERE id = ?'
    }.freeze

    def self.builder(id)
      run = CbbdReviewRun.find(id)
      verify_run(run)
      FixtureComparison.new(season: run.season, replay: run.normalized_replay)
    end

    def self.verify_run(run)
      manifest = run.manifest
      replay = run.normalized_replay
      unless manifest['finalized'] && manifest.fetch('acquisition').fetch('captures').empty? && replay
        raise 'Unexpected synthetic CBBD acquisition'
      end

      actual = Departures::CanonicalDigest.new.call([manifest, replay])
      raise 'Synthetic CBBD evidence changed' unless run.evidence_digest == actual
    end

    def self.persist(builder, id)
      report = builder.call
      values = { 'report' => report, 'replay' => builder.replay }
      digest = Departures::CanonicalDigest.new.call(values.values_at('report', 'replay'))
      CbbdReviewRun.transaction { write_new(id, values, digest) }
    end

    def self.write_new(id, values, digest)
      run = owned_run(id)
      comparison = run.comparisons.create!(version: 1, replay: {}, report: {}, draft: {}, artifact_digest: digest)
      publish_new(run, comparison, values)
    end

    def self.owned_run(id)
      Fixture.guard!
      run = CbbdReviewRun.select(:id, :season_id, :active_comparison_id, :evidence_digest).find(id)
      run.lock!
      verify_new(run, run.comparisons)
      run
    end

    def self.publish_new(run, comparison, values)
      id = comparison.id
      write_columns(id, values)
      run.update!(active_comparison: comparison)
      id
    end

    def self.verify_new(run, comparisons)
      raise 'Refusing to replace an existing comparison' if run.active_comparison_id || comparisons.exists?
    end

    def self.write_columns(id, values)
      values.each do |column, value|
        expected = Departures::CanonicalDigest.new.call(value)
        write_column(id, COLUMNS.fetch(column), value)
        verify_column(id, column, expected)
      end
    end

    def self.write_column(id, column, value)
      query = CbbdReviewComparison.sanitize_sql_array([UPDATES.fetch(column), JSON.generate(value), Integer(id)])
      CbbdReviewComparison.connection.execute(query)
    end

    def self.verify_column(id, column, expected)
      actual = Departures::CanonicalDigest.new.call(JSON.parse(column_json(id, column)))
      matches = actual == expected
      raise 'Synthetic comparison write changed content' unless matches
    end

    def self.column_json(id, column)
      projection = COLUMNS.fetch(column) == 'report' ? 'report::text' : 'replay::text'
      query = CbbdReviewComparison.where(id: Integer(id)).select(Arel.sql(projection))
      CbbdReviewComparison.connection.select_value(query.arel)
    end
  end
end
