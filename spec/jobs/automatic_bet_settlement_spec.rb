# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe 'Automatic bet settlement', type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  self.use_transactional_tests = false

  let!(:fixture) { build_daily_forecast }
  let(:game) { fixture[0] }
  let(:prediction) { fixture[1] }
  let(:odds) { fixture[2] }
  let(:version) { fixture[3] }
  let(:issue) { BetRecommendationIssue.order(:id).last }

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    previous_settlement = SettleBetRecommendationsJob.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    SettleBetRecommendationsJob.queue_adapter = ActiveJob::Base.queue_adapter
    travel_to(Time.utc(2024, 11, 8, 12)) { example.run }
  ensure
    ActiveJob::Base.queue_adapter = previous
    SettleBetRecommendationsJob.queue_adapter = previous_settlement
  end

  before do
    game.update!(home_team_name: game.home_team.school, away_team_name: game.away_team.school)
    BetRecommendationGenerator.call(game: game.reload)
    base = BetRecommendationIssue.last
    BetRecommendationIssue.create!(game: game, prediction: prediction, ratings_config_version: version,
                                   issued_at: Time.current, captured_start_time: game.start_time,
                                   odds_fetched_at: odds.fetched_at,
                                   evidence: base.evidence.merge('markets' => {
                                                                   'spread' => pick('away', 5), 'moneyline' => pick('away', nil, 150),
                                                                   'total' => pick('over', 140)
                                                                 }))
    clear_enqueued_jobs
  end

  after do
    GoodJob::Job.where(job_class: 'SettleBetRecommendationsJob').destroy_all
    GameObservation.delete_all
    GameExternalIdentity.delete_all
    Season.destroy_all
    Team.destroy_all
    RatingsConfigVersion.destroy_all
  end

  def pick(team, line = nil, price = -110)
    { 'team' => team, 'vegas_line' => line, 'vegas_odds' => price, 'confidence' => 0.6,
      'recommended' => true, 'ev' => 0.1, 'model_value' => 0.6 }
  end

  def box(points)
    free_throws = points.odd? ? 16 : 15
    made = (points - 5 - free_throws) / 2
    { minutes: 200, points:, field_goals_made: made, field_goals_attempted: 65,
      two_pt_made: made - 5, two_pt_attempted: 45, three_pt_made: 5, three_pt_attempted: 20,
      free_throws_made: free_throws, free_throws_attempted: 20, offensive_rebounds: 10, defensive_rebounds: 25,
      rebounds: 35, assists: 15, steals: 5, blocks: 3, turnovers: 12, fouls: 17 }
  end

  def import_final(home_score: 70)
    payload = { contract_version: 'ingestion-v1', semantic_profile: 'official-team-totals-v1', provider: 'synthetic',
                external_game_id: game.id.to_s, season_year: game.season.year,
                schedule_date: game.schedule_date.iso8601, start_time: game.start_time.iso8601,
                source_status: 'final', source_completed: true, completion_evidence: 'synthetic-final',
                captured_at: Time.current.iso8601, source_updated_at: Time.current.iso8601,
                source_url: game.url, adapter_revision: 'test-1', duration_minutes: 40,
                home: { name: game.home_team_name, score: home_score, stats: box(home_score) },
                away: { name: game.away_team_name, score: 80, stats: box(80) } }
    ingest(payload)
  end

  def ingest(payload)
    report = Ingestion::GameObservationImporter.new(observation: payload, season: game.season).call
    expect(report).to include(outcome: 'final', accepted: true, game_id: game.id)
  end

  it 'settles a canonical final only after the outer commit and reuses rows for corrections', :aggregate_failures do
    Game.transaction do
      import_final
      expect(enqueued_jobs).to be_empty
    end
    expect(enqueued_jobs).not_to be_empty
    perform_enqueued_jobs
    rows = BetSettlement.where(game: game).order(:bet_type)
    expect(rows.pluck(:bet_type, :status, :stake)).to eq([%w[moneyline win] + [1], %w[spread win] + [1], %w[total win] + [1]])
    expect(rows.pluck(:net_units)).to eq([1.5, 100.0 / 110, 100.0 / 110])
    expect(rows.pluck(:prediction_id, :bet_recommendation_issue_id, :ratings_config_version_id).uniq)
      .to eq([[prediction.id, issue.id, version.id]])
    ids = rows.pluck(:id)
    travel 1.minute
    perform_enqueued_jobs { import_final(home_score: 85) }
    expect(rows.pluck(:id)).to eq(ids)
    expect(rows.pluck(:status, :net_units)).to eq([['loss', -1], ['push', 0], ['win', 100.0 / 110]])
  end

  it 'discards the handoff and canonical final when the outer transaction rolls back' do
    Game.transaction do
      import_final
      expect(enqueued_jobs).to be_empty
      raise ActiveRecord::Rollback
    end
    expect(enqueued_jobs).to be_empty
    expect(game.reload).to be_scheduled
  end

  it 'ignores deleted IDs while settling valid games without a spurious retry' do
    import_final
    clear_enqueued_jobs
    SettleBetRecommendationsJob.perform_now([game.id, game.id, -1])
    expect(BetSettlement.where(game: game).count).to eq(3)
    expect(enqueued_jobs).to be_empty
  end

  it 'rolls back one failed game, preserves another and retries without importing again', :aggregate_failures do
    import_final
    failed = game.dup
    failed.assign_attributes(home_team_name: 'Other home', away_team_name: 'Other away')
    failed.save!
    stale = BetSettlement.create!(game: failed, ratings_config_version: version, bet_type: 'spread',
                                  status: 'win', stake: 1, net_units: 1)
    inject_write_failure(failed.id)
    clear_enqueued_jobs
    allow(Rails.logger).to receive(:error).and_call_original
    SettleBetRecommendationsJob.perform_now([failed.id, game.id])
    expect(BetSettlement.where(game: game).count).to eq(3)
    expect(BetSettlement.where(game: failed).count).to eq(1)
    expect(stale.reload).to have_attributes(status: 'win', stake: 1, net_units: 1)
    expect(Rails.logger).to have_received(:error).with(/game_id=#{failed.id} .*Synthetic write failure/)
    expect(enqueued_jobs.sole[:args]).to eq([[failed.id, game.id]])
    allow(BetSettlement).to receive(:find_or_initialize_by).and_call_original
    perform_enqueued_jobs
    expect(BetSettlement.where(game: failed).pluck(:status, :stake, :net_units).uniq).to eq([['excluded', 0, nil]])
    expect(BetSettlement.where(game: [failed, game]).count).to eq(6)
  end

  it 'captures both moved side IDs before another save and invalidates the old participants', :aggregate_failures do
    import_final
    perform_enqueued_jobs
    destination = game.dup
    destination.assign_attributes(home_team_name: 'Destination home', away_team_name: 'Destination away')
    destination.save!
    BetSettlement.create!(game: destination, ratings_config_version: version, bet_type: 'spread', status: 'pending', stake: 0)
    clear_enqueued_jobs
    side = game.reload.home_team_game
    Game.transaction do
      side.update!(game: destination)
      side.update!(assists: 20)
      expect(enqueued_jobs).to be_empty
    end
    expect(enqueued_jobs.flat_map { |job| job[:args].first }.sort).to eq([game.id, destination.id].sort)
    perform_enqueued_jobs
    expect(BetSettlement.where(game: game).pluck(:status, :stake, :net_units).uniq).to eq([['excluded', 0, nil]])
    clear_enqueued_jobs
    side.destroy!
    expect(enqueued_jobs.flat_map { |job| job[:args].first }).to include(destination.id)
  end

  it 'hands off outcome/provenance changes but ignores derived stats and games without saved evidence', :aggregate_failures do
    [{ home_team_name: 'Corrected label' }, { start_time: game.start_time + 1.hour },
     { status: :canceled }, { status: :scheduled }, { home_team_score: 70 }, { away_team_score: 80 }].each do |attributes|
      clear_enqueued_jobs
      game.update!(attributes)
      expect(enqueued_jobs.sole[:args]).to eq([[game.id]])
    end
    clear_enqueued_jobs
    game.update!(possessions: 75, minutes: 40)
    game.home_team_game.update!(assists: 20)
    no_issue = create(:game, season: game.season)
    no_issue.update!(status: :final, home_team_score: 80, away_team_score: 70)
    expect(enqueued_jobs).to be_empty
  end

  it 'stores a GoodJob retry after a committed import survives later work failure and recovers without reimport', :aggregate_failures do
    previous = SettleBetRecommendationsJob.queue_adapter
    SettleBetRecommendationsJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    begin
      expect do
        Game.transaction do
          import_final
          expect(GoodJob::Job.where(job_class: 'SettleBetRecommendationsJob')).to be_empty
        end
        raise 'Later analytics failure'
      end.to raise_error('Later analytics failure')
      stored = GoodJob::Job.where(job_class: 'SettleBetRecommendationsJob').first!
      inject_write_failure(game.id)
      delivery = GoodJob::Job.where(id: stored.id).perform_with_advisory_lock(lock_id: SecureRandom.uuid)
      expect(delivery).to be_retried
      expect(BetSettlement.where(game: game)).to be_empty
      expect(stored.reload).to have_attributes(finished_at: nil, executions_count: 1)
      expect(stored.error).to include("game IDs: #{game.id}")
      expect(stored.serialized_params['executions']).to eq(1)
      allow(BetSettlement).to receive(:find_or_initialize_by).and_call_original
      travel_to(stored.scheduled_at + 1.second)
      recovered = GoodJob::Job.where(id: stored.id).perform_with_advisory_lock(lock_id: SecureRandom.uuid)
      expect(recovered).not_to be_retried
      expect(recovered.unhandled_error).to be_nil
      expect(BetSettlement.where(game: game).pluck(:status, :stake).uniq).to eq([['win', 1]])
      expect(BetSettlement.where(game: game).count).to eq(3)
    ensure
      SettleBetRecommendationsJob.queue_adapter = previous
    end
  end

  it 'defers settlement while another connection holds the heavy lock and retains explicit IDs', :aggregate_failures do
    import_final
    clear_enqueued_jobs
    ready = Queue.new
    release = Queue.new
    holder = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        GoodJob::Job.advisory_lock_key(HeavyJob::LOCK_KEY) do
          ready << true
          release.pop
        end
      end
    end
    begin
      Timeout.timeout(5) { ready.pop }
      ids = [game.id, game.id]
      expect { SettleBetRecommendationsJob.perform_now(ids) }
        .to have_enqueued_job(SettleBetRecommendationsJob).with(ids).on_queue('heavy').at(5.seconds.from_now)
      expect(BetSettlement.where(game:)).to be_empty
    ensure
      release << true
      holder.join(5)
    end
    perform_enqueued_jobs
    expect(BetSettlement.where(game:).pluck(:status, :stake).uniq).to eq([['win', 1]])
    expect(BetSettlement.where(game:).count).to eq(3)
  end

  it 'invalidates participant-only corrections and removal after commit', :aggregate_failures do
    import_final
    perform_enqueued_jobs
    replacement = create(:team_season, season: game.season)
    perform_enqueued_jobs do
      game.reload.home_team_game.update!(team: replacement.team, team_season: replacement)
    end
    expect(BetSettlement.where(game:).pluck(:status, :stake, :net_units).uniq).to eq([['excluded', 0, nil]])
    clear_enqueued_jobs
    game.reload.away_team_game.destroy!
    expect(enqueued_jobs.sole[:args]).to eq([[game.id]])
  end

  it 'surfaces enqueue failure after commit and supports explicit-ID recovery without another import', :aggregate_failures do
    allow(SettleBetRecommendationsJob).to receive(:perform_later).and_return(false)
    expect { game.update!(status: :final, home_team_score: 70, away_team_score: 80) }
      .to raise_error(ActiveJob::EnqueueError, /game_id=#{game.id}/)
    expect(game.reload).to be_final
    expect(BetSettlement.where(game:)).to be_empty
    allow(SettleBetRecommendationsJob).to receive(:perform_later).and_call_original
    perform_enqueued_jobs { SettleBetRecommendationsJob.perform_later([game.id]) }
    expect(BetSettlement.where(game:).pluck(:status, :stake).uniq).to eq([['win', 1]])
  end

  def inject_write_failure(game_id)
    allow(BetSettlement).to receive(:find_or_initialize_by).and_wrap_original do |method, **identity|
      row = method.call(**identity)
      if identity[:game].id == game_id && identity[:bet_type] == 'total'
        allow(row).to receive(:update!).and_wrap_original do |update, **attributes|
          update.call(**attributes)
          raise 'Synthetic write failure'
        end
      end
      row
    end
  end
end
