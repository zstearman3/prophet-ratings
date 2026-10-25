# frozen_string_literal: true

module OffseasonPerformance
  # Verifies real queued transitions and immutable comparison outputs after each HTTP request.
  class JobDriver
    QUEUE_CLASSES = { 'preview' => 'PreviewPreseasonJob', 'publish' => 'PublishPreseasonJob', 'schedule' => 'RefreshScheduleJob',
                      'compare' => 'CompareCbbdReviewJob' }.freeze

    def initialize(scenario)
      @scenario = scenario
    end

    def prepare
      state = { 'publication' => (reviewed_preview if @scenario.publish?),
                'before_job' => GoodJob::Job.maximum(:created_at) || Time.zone.at(0) }
      if @scenario.comparison?
        state['comparison_identity'] = comparison_identity
        state['before_comparison'] = CbbdReviewComparison.maximum(:id)
      end
      state
    end

    def complete(result, state)
      comparison = state['comparison_identity']
      return result unless @scenario.queued? || comparison

      job = completed_job(result, state.fetch('before_job'))
      result.merge!(comparison ? comparison_result(job, comparison,
                                                   state.fetch('before_comparison')) : { 'terminal' => terminal(job, state) })
    end

    def completed_job(result, before)
      job = new_job(before)
      result['worker'] = JobDriver.wait_job(job.active_job_id)
      job
    end

    def comparison_result(job, identity, before)
      raise 'Comparison pin mismatch' unless JobDriver.pin_matches?(job, identity)

      { 'comparison_id' => self.class.comparison(before, @scenario.fixture.fetch('cbbd_id')) }
    end

    def self.pin_matches?(job, identity)
      ActiveJob::Arguments.deserialize(job.serialized_params.fetch('arguments')) == identity
    end

    def self.comparison(before, run_id)
      pointer = CbbdReviewRun.where(id: run_id).pick(:active_comparison_id)
      comparison = CbbdReviewComparison.where(cbbd_review_run_id: run_id).where('id > ?', before.to_i).find(pointer)
      comparison.verify_artifact
      comparison.id
    end

    def comparison_identity
      run = CbbdReviewRun.select(:id, :evidence_digest, :active_comparison_id).find(@scenario.fixture.fetch('cbbd_id'))
      [run.id, Ingestion::Reconciliation::RunReview.new(run).comparison_identity]
    end

    def reviewed_preview
      publication = PreseasonPublication.review!(Season.find(@scenario.fixture.fetch('season_id')),
                                                 reviewer: User.find_by!(admin: true), mode: 'initialize')
      JobDriver.await_preview(publication)
    end

    def self.await_preview(publication)
      job = GoodJob::Job.where(job_class: 'PreviewPreseasonJob', queue_name: JobDriver.queue).order(created_at: :desc).first!
      JobDriver.wait_job(job.active_job_id)
      publication.reload
      JobDriver.verify_preview(publication, 'review')
      publication
    end

    def new_job(before)
      name = @scenario.name
      driver = self.class
      job = GoodJob::Job.where(job_class: QUEUE_CLASSES.fetch(name), queue_name: driver.queue)
                        .where('created_at > ?', before).order(created_at: :desc).first!
      driver.verify_identity(job, name)
      job
    end

    def self.queue
      PhaseQueue.name(ENV.fetch('BENCHMARK_OWNER'), ENV.fetch('BENCHMARK_PHASE'), 'heavy')
    end

    def self.verify_identity(job, name)
      raise 'Wrong queued job' unless job.job_class == QUEUE_CLASSES.fetch(name) && job.queue_name == queue
    end

    def self.wait_job(id)
      deadline = Telemetry.now + 180
      loop do
        row = poll_job(id, deadline)
        return row if row

        sleep 0.2
      end
    end

    def self.poll_job(id, deadline)
      row = Measurements.journal('job', id)
      verify_job_output(row, id) if row
      raise "Worker timeout #{id}" if !row && Telemetry.now > deadline

      row
    end

    def self.verify_job_output(row, id)
      raise "Job failed #{id}" unless row['terminal'] == 'performed'

      bytes = row['output_bytes']
      valid = bytes.is_a?(Numeric) && bytes >= 0
      raise "Missing job output bytes #{id}" unless valid
    end

    def terminal(job, state)
      id = job.serialized_params.fetch('arguments').first
      return self.class.schedule_terminal(id) if @scenario.name == 'schedule'

      publication_terminal(id, state)
    end

    def publication_terminal(id, state)
      record = state['publication'] || PreseasonPublication.find(id)
      record.reload
      JobDriver.verify_preview(record, @scenario.expected_status)
      @scenario.publish? ? JobDriver.published(record) : JobDriver.publication_summary(record)
    end

    def self.verify_preview(record, expected)
      status = record.status
      matches = status == expected
      raise "Publication terminal #{status}" unless matches
      raise 'Expected 365 preview teams' unless record.report.fetch('teams').size == 365
    end

    def self.publication_summary(record)
      { 'publication_id' => record.id, 'status' => record.status }
    end

    def self.published(record)
      ids = record.result.slice('capture_ids', 'snapshot_ids')
      verify_published(record, ids)
      publication_summary(record).merge(ids, 'model_id' => record.ratings_config_version_id, 'season_id' => record.season_id)
    end

    def self.verify_published(record, ids)
      captures = ids.fetch('capture_ids')
      snapshots = ids.fetch('snapshot_ids')
      raise 'Expected 365 published snapshots and captured priors' unless captures.size == 365 && snapshots.size == 365

      verify_provenance(record, ids)
    end

    def self.verify_provenance(record, ids)
      scope = { ratings_config_version_id: record.ratings_config_version_id }
      priors = PreseasonPrior.where(id: ids.fetch('capture_ids'), **scope, team_season_id: record.season.team_seasons.select(:id)).count
      snapshots = TeamRatingSnapshot.where(id: ids.fetch('snapshot_ids'), **scope, season_id: record.season_id).count
      raise 'Published prior/snapshot provenance mismatch' unless priors == 365 && snapshots == 365
    end

    def self.schedule_terminal(id)
      run = ScheduleRefreshRun.find(id)
      verify_schedule_run(run)
      game = schedule_game
      verify_schedule_observation(run, game)
      { 'status' => run.status, 'game_id' => game.id, 'observations' => GameObservation.where(provider: 'cbbd').count }
    end

    def self.verify_schedule_run(run)
      status = run.status
      raise "Schedule import #{status}: #{run.error}" unless status == 'succeeded'
    end

    def self.schedule_game
      identities = GameExternalIdentity.active.where(provider: 'cbbd', external_id: '900001')
      raise 'Expected stable imported game missing' unless identities.one?

      Game.find(identities.first.game_id)
    end

    def self.verify_schedule_observation(run, game)
      verify_scores(game)
      game_id = game.id
      return if run.report_game_ids.include?(game_id) && GameObservation.exists?(provider: 'cbbd', game_id:, accepted: true)

      raise "Schedule accepted observation missing: #{run.report.inspect}"
    end

    def self.verify_scores(game)
      return if game.status == 'final' && game.home_team_score == 65 && game.away_team_score == 64

      raise 'Unexpected imported final scores'
    end
  end
end
