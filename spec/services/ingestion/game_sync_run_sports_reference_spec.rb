# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::GameSyncRun do
  let(:date) { Date.new(2026, 2, 21) }
  let(:season) { create(:season, year: 2026, start_date: date - 1, end_date: date + 2) }
  let(:home) { create(:team, school: 'Coverage Home') }
  let(:away) { create(:team, school: 'Coverage Away') }
  let(:home_stats) do
    { minutes: 200, field_goals_made: 25, field_goals_attempted: 55, two_pt_made: 20, two_pt_attempted: 40,
      three_pt_made: 5, three_pt_attempted: 15, free_throws_made: 10, free_throws_attempted: 12,
      offensive_rebounds: 8, defensive_rebounds: 22, rebounds: 30, assists: 12, steals: 5, blocks: 3,
      turnovers: 10, fouls: 15, points: 65 }
  end
  let(:away_stats) do
    { minutes: 200, field_goals_made: 24, field_goals_attempted: 58, two_pt_made: 18, two_pt_attempted: 40,
      three_pt_made: 6, three_pt_attempted: 18, free_throws_made: 10, free_throws_attempted: 14,
      offensive_rebounds: 7, defensive_rebounds: 21, rebounds: 28, assists: 10, steals: 4, blocks: 2,
      turnovers: 11, fouls: 16, points: 64 }
  end
  let(:row) do
    { date:, home_team: home.school, away_team: away.school, home_team_score: 65, away_team_score: 64,
      home_team_stats: home_stats, away_team_stats: away_stats, source_completed: true,
      source_completion_evidence: 'boxscore', url: '/cbb/boxscores/2026-02-21-coverage.html' }
  end
  let(:scraper) { instance_double(Scraper::GamesScraper, game_count: 1, to_json_in_batches: [row]) }
  let(:enricher) { instance_double(Ingestion::GameRowEnricher) }

  before do
    [home, away].each { |team| create(:team_season, team:, season:) }
    allow(Game).to receive(:current_schedule_date).and_return(date + 1)
    empty = instance_double(Scraper::GamesScraper, game_count: 0)
    allow(Scraper::GamesScraper).to receive(:new).and_return(empty)
    allow(Scraper::GamesScraper).to receive(:new).with(date).and_return(scraper)
    allow(Ingestion::GameRowEnricher).to receive(:new).and_return(enricher)
    allow(enricher).to receive(:call) { |rows| rows }
    allow(Ingestion::HistoricalSyncDay).to receive(:new).and_wrap_original do |original, **arguments|
      original.call(**arguments).tap { |day| allow(day).to receive(:sleep) }
    end
  end

  def historical_day
    Ingestion::HistoricalSyncDay.new(season:, date:, resume: false).call
  end

  def domain_state
    [Game.order(:id).map(&:attributes), TeamGame.order(:id).map(&:attributes),
     GameExternalIdentity.order(:id).map(&:attributes), GameObservation.where(accepted: true).order(:id).map(&:attributes)]
  end

  def remove_source_boxes
    row.merge!(home_team_stats: {}, away_team_stats: {})
  end

  it 'classifies complete source finals and unchanged complete finals from the current observation' do
    first = historical_day
    expect(first).to include(status: 'completed', complete: true, final_box_coverage: { 'complete' => 1 })
    expect(Game.last).to be_final
    state = domain_state
    second = historical_day
    expect(second[:games].first).to include(outcome: 'unchanged', final_box: 'complete')
    expect(domain_state).to eq(state)
  end

  %w[scheduled live].each do |status|
    it "classifies #{status} source observations without final boxes as not_final" do
      row.merge!(source_status: status, source_completed: false, source_completion_evidence: nil,
                 home_team_score: nil, away_team_score: nil)
      remove_source_boxes
      row[:home_team_stats][:assists] = ' '
      expect(historical_day).to include(status: 'completed', complete: true, final_box_coverage: { 'not_final' => 1 })
      expect(GameObservation.last.normalized_payload['source_status']).to eq(status)
      expect(GameObservation.last.normalized_payload.dig('home', 'field_availability', 'assists')).to eq('blank')
    end
  end

  it 'holds matching stored finals with missing source boxes and preserves accepted domain/audit state', :aggregate_failures do
    historical_day
    state = domain_state
    remove_source_boxes
    result = historical_day
    expect(result).to include(status: 'failed', complete: false, rolled_back: true, final_box_coverage: { 'missing' => 1 })
    expect(result[:counts]).to include(accepted: 0, incomplete: 1)
    expect(GameSyncDate.last).to have_attributes(status: 'failed', completed_at: nil, attempts: 7)
    expect(domain_state).to eq(state)
    expect(GameObservation.where(accepted: false)).to all(have_attributes(game_id: nil, reason: /date_rolled_back/))
    expect(GameObservation.last.raw_payload['home_team_stats']).to eq({})
  end

  it 'holds matching stored finals during future refresh without asserting source absence' do
    historical_day
    state = domain_state
    remove_source_boxes
    allow(Game).to receive(:current_schedule_date).and_return(date)
    refresh = Ingestion::FutureScheduleRefresh.new(season:, start_date: date, end_date: date)
    allow(refresh).to receive(:sleep)
    result = refresh.call
    expect(result).to include(complete: false, failed_dates: [date], absent_ids: [])
    expect(result[:days].first[:final_box_coverage]).to eq('missing' => 1)
    expect(domain_state).to eq(state)
    expect(GameSyncDate.last).to have_attributes(status: 'completed', attempts: 1)
  end

  it 'suppresses nightly rankings when matching stored finals lack current source boxes' do
    historical_day
    state = domain_state
    remove_source_boxes
    allow(UpdateRankingsJob).to receive(:perform_later)
    operation = lambda do
      SyncNightlyGamesJob.new.perform(season.id, past_lookback_days: 1, future_end_date: date + 1)
    end
    expect(&operation).to raise_error(SyncFullSeasonGamesJob::IncompleteSync) do |error|
      expect(error.report[:days].first[:final_box_coverage]).to eq('missing' => 1)
    end
    expect(UpdateRankingsJob).not_to have_received(:perform_later)
    expect(domain_state).to eq(state)
    expect(GameSyncDate.find_by!(schedule_date: date).status).to eq('failed')
  end

  it 'reports invalid final source counts without certifying box coverage' do
    row[:home_team_stats][:minutes] = 'invalid'
    expect(historical_day).to include(status: 'failed', complete: false, final_box_coverage: { 'invalid' => 1 })
    expect(Game.count).to eq(0)
  end
end
