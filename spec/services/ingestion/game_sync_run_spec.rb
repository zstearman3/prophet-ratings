# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe Ingestion::GameSyncRun do
  include ActiveJob::TestHelper

  around do |example|
    adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = adapter
  end

  before do
    clear_enqueued_jobs
    allow(Game).to receive(:current_schedule_date).and_return(date + 3)
    [home, away].zip(%w[10 20]).each do |team, external_id|
      create(:team_season, team:, season:)
      TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id:)
    end
  end

  let(:date) { Date.new(2025, 11, 1) }
  let(:season) { create(:season, year: 2026, start_date: date, end_date: date + 20) }
  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/ingestion/cbbd/final.json').read) }
  let(:directory) { Dir.mktmpdir('provider-sync') }
  let(:requests) { [] }
  let(:transport) do
    lambda do |uri, _key|
      requests << uri
      { status: 200, headers: {}, body: fixture.fetch(uri.path == '/games' ? 'games' : 'boxes').to_json }
    end
  end
  let(:options) { { api_key: 'synthetic-private', capture_directory: directory, max_requests: 2, retries: 0, transport: } }
  let(:home) { create(:team, school: 'Synthetic Home') }
  let(:away) { create(:team, school: 'Synthetic Away') }

  after { FileUtils.remove_entry(directory) }

  def sync(**arguments)
    SyncFullSeasonGamesJob.new.perform(season, provider: 'cbbd', provider_options: options, **arguments)
  end

  def schedule_only!
    fixture['games'].first.merge!('status' => 'scheduled', 'homePoints' => 0, 'awayPoints' => 0)
    fixture['boxes'] = []
  end

  it 'imports a real normalized official final and commits its provider-scoped checkpoint' do
    result = sync
    expect(result).to include(complete: true, retrieval_complete: true, attempts: 2)
    expect(requests.length).to eq(2)
    expect(Game.last).to have_attributes(status: 'final', home_team_score: 65, away_team_score: 64, minutes: 40)
    expect(GameObservation.where(accepted: true).sole.normalized_payload).to include('source_updated_at' => nil)
    expect(result[:days].first[:final_box_coverage]).to eq('complete' => 1)
  end

  it 'keeps source missingness and observed zeros in raw provenance and protects manual venue' do
    schedule_only!
    fixture['games'].first['neutralSite'] = true
    result = sync
    game = Game.last
    expect(game).to have_attributes(home_team_score: nil, neutral: true)
    audit = GameObservation.find(result[:days].first[:games].first[:observation_id])
    expect(audit.raw_payload.dig('home', 'score')).to include('value' => nil, 'reason' => 'nonfinal_placeholder')
    game.update!(venue_confidence: 'manual', venue_source: 'manual_override', neutral: false, venue_type: 'home')
    requests.clear
    expect(sync(resume: false)[:complete]).to be(true)
    expect(game.reload).to have_attributes(neutral: false, venue_source: 'manual_override')
  end

  it 'does not reuse legacy, scraper or older-revision completion evidence' do
    GameSyncDate.create!(season:, schedule_date: date, status: 'completed')
    scope = Ingestion::GameSyncPolicy.new('cbbd', options).scope
    GameSyncDate.create!(season:, schedule_date: date, status: 'completed', **scope.merge(adapter_revision: 'old'))
    expect(sync[:days].first[:status]).to eq('completed')
    expect(GameSyncDate.where(schedule_date: date).count).to eq(3)
    requests.clear
    expect(sync[:days].pluck(:status)).to eq(%w[skipped skipped skipped])
    expect(requests).to be_empty
  end

  it 'filters completed interior resume dates even when acquisition spans both holes' do
    scope = Ingestion::GameSyncPolicy.new('cbbd', options).scope
    checkpoint = GameSyncDate.create!(season:, schedule_date: date + 1, status: 'completed', attempts: 3, **scope)
    fixture['games'].first['startDate'] = '2025-11-02T23:00:00Z'
    fixture['boxes'].each { |box| box['startDate'] = '2025-11-02T23:00:00Z' }
    report = sync
    expect(report).to include(complete: true, ignored_observations: 1)
    expect(Game.count).to eq(0)
    expect(checkpoint.reload.attempts).to eq(3)
    expect(report[:days].pluck(:status)).to eq(%w[completed skipped completed])
  end

  it 'rolls back an earlier accepted row and accepted-incomplete row and retains rejected evidence safely', :aggregate_failures do
    other_home = create(:team, school: 'Other Home')
    create(:team_season, team: other_home, season:)
    TeamExternalIdentity.associate!(team: other_home, provider: 'cbbd', external_id: '30')
    other = fixture['games'].first.deep_dup.merge('id' => 2, 'homeTeamId' => 30, 'homeTeam' => other_home.school,
                                                  'startDate' => '2025-11-01T22:00:00Z')
    fixture['games'] << other
    fixture['boxes'] = []
    schedule_only = fixture['games'].first
    schedule_only.merge!('status' => 'scheduled', 'homePoints' => 0, 'awayPoints' => 0)
    expect { sync }.to raise_error(Ingestion::GameSyncProvider::Incomplete) do |error|
      expect(error.report[:failed_dates]).to eq([date])
    end
    expect([Game.count, TeamGame.count, GameExternalIdentity.count]).to eq([0, 0, 0])
    expect(GameObservation.where(accepted: true)).to be_empty
    audit = GameObservation.where(outcome: 'incomplete').sole
    expect(audit).to have_attributes(game_id: nil, accepted: false, reason: 'date_rolled_back: missing_required_box_data')
    expect(audit.raw_payload['source_game_id']).to eq(2)
  end

  it 'reports unmatched teams as unfinished rather than successful empties' do
    TeamExternalIdentity.where(team: away).delete_all
    expect { sync }.to raise_error(Ingestion::GameSyncProvider::Incomplete)
    expect(GameSyncDate.find_by!(schedule_date: date)).to have_attributes(status: 'failed', attempts: 1)
    expect(GameObservation.last.outcome).to eq('unmatched')
    expect(Game.count).to eq(0)
  end

  it 'holds invalid numeric finals and normalized conflicts before domain persistence' do
    fixture['boxes'].first['teamStats']['fieldGoals']['made'] = 99
    expect { sync }.to raise_error(Ingestion::GameSyncProvider::Incomplete)
    expect(Game.count).to eq(0)
    expect(GameSyncDate.where(status: 'completed').count).to eq(0)
  end

  it 'uses one budget across the whole nightly correction and future range' do
    fixture['games'] = []
    fixture['boxes'] = []
    report = SyncNightlyGamesJob.new.perform(season.id, provider: 'cbbd', provider_options: options,
                                                        past_lookback_days: 2, future_end_date: date + 5)
    expect(report).to include(complete: true, attempts: 2)
    expect(requests.length).to eq(2)
    expect(report[:days].pluck(:date)).to eq(((date + 1)..(date + 5)).to_a)
  end

  it 'does not renew exhausted budgets through ActiveJob retries or enqueue follow-up jobs' do
    options[:max_requests] = 1
    allow(UpdateRankingsJob).to receive(:perform_later)
    allow(RepairDuplicateGamesJob).to receive(:perform_later)
    expect do
      SyncFullSeasonGamesJob.perform_now(season.id, provider: 'cbbd', provider_options: options, dedupe: true)
    end.to raise_error(Ingestion::GameSyncProvider::Incomplete)
    expect(requests.length).to eq(1)
    expect(enqueued_jobs).to be_empty
    expect(UpdateRankingsJob).not_to have_received(:perform_later)
    expect(RepairDuplicateGamesJob).not_to have_received(:perform_later)
  end

  [401, 429, 503].each do |status|
    it "does not automatically retry the whole async nightly run after HTTP #{status}" do
      options[:transport] = lambda do |uri, _key|
        requests << uri
        { status:, headers: {}, body: 'synthetic-private' }
      end
      operation = lambda do
        SyncNightlyGamesJob.perform_now(season.id, provider: 'cbbd', provider_options: options,
                                                   past_lookback_days: 2, future_end_date: date + 5)
      end
      expect(&operation).to raise_error(Ingestion::GameSyncProvider::Incomplete) do |error|
        expect(error.report.to_json).not_to include('synthetic-private')
      end
      expect(requests.length).to eq(2)
      expect(enqueued_jobs).to be_empty
      expect(Game.count).to eq(0)
    end
  end
  it 'keeps live rows valid without certifying missing final boxes' do
    schedule_only!
    fixture['games'].first.merge!('status' => 'in_progress', 'homePoints' => 2, 'awayPoints' => 0)
    report = sync
    expect(report[:complete]).to be(true)
    expect(report[:days].first[:games].first).to include(outcome: 'live', final_box: 'not_final')
    expect(Game.last.away_team_score).to eq(0)
    expect(GameObservation.last.raw_payload.dig('away', 'score', 'value')).to eq(0)
  end

  it 'recognizes unchanged finals but holds corrections without invented upstream freshness' do
    sync
    report = sync(resume: false)
    expect(report[:days].first[:games].first).to include(outcome: 'unchanged')
    fixture['games'].first['neutralSite'] = true
    fixture['boxes'].each { |box| box['neutralSite'] = true }
    expect { sync(resume: false) }.to raise_error(Ingestion::GameSyncProvider::Incomplete) do |error|
      expect(error.report[:days].first).to include(rolled_back: true, outcomes: { 'conflict' => 1 })
    end
    expect(Game.last.neutral).not_to be(true)
  end

  it 'refreshes CBBD future dates repeatedly without interpreting source absence as deletion' do
    allow(Game).to receive(:current_schedule_date).and_return(date)
    schedule_only!
    arguments = { season:, start_date: date, end_date: date + 1, provider: 'cbbd', provider_options: options }
    first = Ingestion::FutureScheduleRefresh.new(**arguments).call
    expect(first[:complete]).to be(true)
    game = Game.last
    fixture['games'] = []
    second = Ingestion::FutureScheduleRefresh.new(**arguments).call
    expect(second).to include(complete: true, absent_ids: [game.id])
    expect(game.reload).to be_scheduled
    expect(requests.length).to eq(4)
  end

  it 'retains incomplete final evidence safely after a future date transaction rolls back' do
    allow(Game).to receive(:current_schedule_date).and_return(date)
    fixture['boxes'] = []
    report = Ingestion::FutureScheduleRefresh.new(season:, start_date: date, end_date: date, provider: 'cbbd',
                                                  provider_options: options).call
    expect(report).to include(complete: false, failed_dates: [date], absent_ids: [])
    expect(report[:days].first).to include(rolled_back: true, counts: include(accepted: 0, incomplete: 1))
    expect(Game.count).to eq(0)
    expect(GameObservation.last).to have_attributes(accepted: false, game_id: nil, outcome: 'incomplete')
  end

  it 'refuses malformed nightly/daily bounds before requesting a source' do
    expect { SyncDailyGamesJob.new.perform(date - 1, season_id: season.id, provider: 'cbbd', provider_options: options) }
      .to raise_error(Ingestion::GameSyncProvider::Incomplete)
    expect { SyncNightlyGamesJob.new.perform(season.id, provider: 'cbbd', provider_options: options) }
      .to raise_error(Ingestion::GameSyncProvider::Incomplete)
    expect do
      SyncNightlyGamesJob.new.perform(season.id, provider: 'cbbd', provider_options: options,
                                                 past_lookback_days: -1, future_end_date: 'bad')
    end.to raise_error(Ingestion::GameSyncProvider::Incomplete)
    expect(requests).to be_empty
  end

  it 'does not enqueue an async retry after held daily rows' do
    TeamExternalIdentity.where(team: away).delete_all
    expect do
      SyncDailyGamesJob.perform_now(date, season_id: season.id, provider: 'cbbd', provider_options: options)
    end.to raise_error(Ingestion::GameSyncProvider::Incomplete)
    expect(requests.length).to eq(2)
    expect(enqueued_jobs).to be_empty
  end

  it 'does not certify final-box coverage from unchanged stored values when new source boxes are missing' do
    sync
    state = Game.last.attributes
    fixture['boxes'] = []
    expect { sync(resume: false) }.to raise_error(Ingestion::GameSyncProvider::Incomplete) do |error|
      expect(error.report[:days].first).to include(rolled_back: true, final_box_coverage: { 'missing' => 1 })
    end
    expect(Game.last.attributes).to eq(state)
    expect(GameSyncDate.find_by!(schedule_date: date).status).to eq('failed')
  end
end
