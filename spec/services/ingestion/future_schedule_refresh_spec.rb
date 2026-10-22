# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::FutureScheduleRefresh do
  let(:today) { Date.new(2026, 11, 1) }
  let(:season) { create(:season, year: 2027, start_date: today, end_date: today + 20.days) }
  let(:refresh) { described_class.new(season:, start_date: today, end_date: today + 2.days) }
  let(:service) { instance_double(Ingestion::GamesIngestionService, call: { imported_rows: 0, games: [] }) }

  before do
    allow(Game).to receive(:current_schedule_date).and_return(today)
    allow(Ingestion::GamesIngestionService).to receive(:new).and_return(service)
    allow(refresh).to receive(:sleep)
  end

  it 'visits every bounded date regardless of existing future games and leaves activation unchanged' do
    create(:game, season:, start_time: Game.schedule_time_for(today + 15.days), status: :scheduled)
    result = refresh.call
    expect(result[:days].pluck(:date)).to eq((today..(today + 2.days)).to_a)
    expect(result[:failed_dates]).to be_empty
    expect(season.reload).not_to be_current
    expect(Ingestion::GamesIngestionService).to have_received(:new).with(date: today, season:)
  end

  it 'reports source absences on successful dates without deleting records' do
    game = create(:game, season:, start_time: Game.schedule_time_for(today), status: :scheduled)
    result = refresh.call
    expect(result[:absent_ids]).to eq([game.id])
    expect(game.reload).to be_scheduled
  end

  it 'reports exhausted retries separately from successful empty dates and continues' do
    failing = instance_double(Ingestion::GamesIngestionService)
    allow(failing).to receive(:call).and_raise(Scraper::GamesScraper::SourceError, 'unavailable')
    allow(Ingestion::GamesIngestionService).to receive(:new).with(date: today, season:).and_return(failing)
    game = create(:game, season:, start_time: Game.schedule_time_for(today), status: :scheduled)
    result = refresh.call
    expect(result[:failed_dates]).to eq([today])
    expect(result[:days].last).to include(imported_rows: 0, date: today + 2.days)
    expect(result[:absent_ids]).not_to include(game.id)
    expect(failing).to have_received(:call).exactly(4).times
  end

  it 'rolls back a partial date before retrying it' do
    allow(service).to receive(:call) do
      create(:game, season:, start_time: Game.schedule_time_for(today), status: :scheduled)
      raise Scraper::GamesScraper::SourceError, 'second batch failed'
    end
    expect(refresh.call[:failed_dates]).to eq((today..(today + 2.days)).to_a)
    expect(Game.count).to eq(0)
  end

  it 'omits a reliably moved game from absence review after later dates succeed' do
    game = create(:game, season:, start_time: Game.schedule_time_for(today), status: :scheduled)
    allow(service).to receive(:call) do
      game.update!(start_time: Game.schedule_time_for(today + 1.day))
      { imported_rows: 1, games: [{ game_id: game.id, outcome: 'updated' }] }
    end
    expect(refresh.call[:absent_ids]).to be_empty
  end

  it 'fails dates with canonical conflicts rather than counting rejected rows as successful refreshes' do
    allow(service).to receive(:call).and_return(imported_rows: 0, games: [{ outcome: 'conflict', reason: 'unknown_source_freshness' }])
    result = refresh.call
    expect(result[:failed_dates]).to eq((today..(today + 2.days)).to_a)
    expect(result[:days].first[:error]).to include('Rejected source games', 'unknown_source_freshness')
    expect(result[:absent_ids]).to be_empty
  end

  it 'imports only selected dates and checkpoints successful rows inside the import transaction' do
    observed = []
    callback = lambda do |day|
      observed << [day[:date], Game.connection.transaction_open?]
    end
    result = described_class.new(season:, start_date: today, end_date: today + 2.days,
                                 dates: [today, today + 2.days], on_day: callback).call
    expect(result[:days].pluck(:date)).to eq([today, today + 2.days])
    expect(observed).to eq([[today, true], [today + 2.days, true]])
    expect(Ingestion::GamesIngestionService).not_to have_received(:new).with(date: today + 1.day, season:)
  end

  it 'rolls back imported games when the durable success checkpoint fails' do
    allow(service).to receive(:call) do
      create(:game, season:, start_time: Game.schedule_time_for(today))
      { imported_rows: 1, games: [] }
    end
    callback = ->(day) { raise ActiveRecord::StatementInvalid, 'checkpoint failed' unless day[:error] }
    subject = described_class.new(season:, start_date: today, end_date: today, on_day: callback)
    allow(subject).to receive(:sleep)
    expect(subject.call[:failed_dates]).to eq([today])
    expect(Game.count).to eq(0)
  end

  it 'rejects empty or out of window selected dates' do
    [[], [today + 3.days]].each do |dates|
      expect { described_class.new(season:, start_date: today, end_date: today + 2.days, dates:) }.to raise_error(ArgumentError)
    end
  end

  context 'with the real canonical service and adapter' do
    let(:scraper) { instance_double(Scraper::GamesScraper) }
    let(:home) { create(:team, school: 'Projected Home') }
    let(:away) { create(:team, school: 'Projected Away') }
    let(:row) do
      { date: today, home_team: home.school, away_team: away.school, source_status: 'scheduled',
        source_completed: false, url: 'https://www.sports-reference.com/cbb/boxscores/index.cgi?day=1' }
    end
    let(:refresh) { described_class.new(season:, start_date: today, end_date: today) }

    before do
      allow(Ingestion::GamesIngestionService).to receive(:new).and_call_original
      allow(Scraper::GamesScraper).to receive(:new).with(today).and_return(scraper)
      allow(scraper).to receive_messages(game_count: 1, to_json_in_batches: [row])
      enrichment = instance_double(Scraper::TeamScheduleEnrichmentScraper, schedule_data: [])
      allow(Scraper::TeamScheduleEnrichmentScraper).to receive(:new).and_return(enrichment)
      [home, away].each { |team| create(:team_season, team:, season:) }
    end

    it 'matches and creates unlinked pregame schedules and counts changed and unchanged projections' do
      absent = create(:game, season:, start_time: Game.schedule_time_for(today), status: :scheduled)
      first = refresh.call
      aggregate_failures do
        expect(first[:failed_dates]).to be_empty
        expect(first[:days].first[:imported_rows]).to eq(1)
        game = Game.find(first[:days].first[:games].first[:game_id])
        expect(game.home_team_season.team).to eq(home)
        expect(first[:absent_ids]).to eq([absent.id])
        second = refresh.call
        expect(second[:days].first[:games].first).to include(game_id: game.id, outcome: 'unchanged', projected: true)
        expect(second[:days].first[:imported_rows]).to eq(1)
        expect(second[:absent_ids]).to eq([absent.id])
      end
    end

    it 'suppresses every absence conclusion on a date with an unresolved scheduled row' do
      game = create(:game, season:, start_time: Game.schedule_time_for(today), status: :scheduled)
      allow(scraper).to receive(:to_json_in_batches).and_return([row.merge(away_team: 'Unknown visitor')])
      result = refresh.call
      expect(result[:failed_dates]).to eq([today])
      expect(GameObservation.last.outcome).to eq('unmatched')
      expect(result[:absent_ids]).not_to include(game.id)
    end

    it 'fails an ambiguous date and rolls back earlier successful projections and their audits' do
      other = create(:team, school: 'Ambiguous Visitor')
      create(:team_alias, team: other, value: away.school, source: 'ambiguous')
      safe = create(:team, school: 'Safe Visitor')
      create(:team_season, team: safe, season:)
      allow(scraper).to receive_messages(game_count: 2, to_json_in_batches: [row.merge(away_team: safe.school), row])
      result = refresh.call
      expect(result[:failed_dates]).to eq([today])
      expect([Game.count, TeamGame.count, GameExternalIdentity.count]).to eq([0, 0, 0])
      expect(GameObservation.where(outcome: 'projected').count).to eq(0)
      expect(GameObservation.where(outcome: 'ambiguous').count).to eq(4)
    end
  end

  it 'rejects missing, reversed, historical and out-of-season windows before ingestion' do
    [[nil, today], [today + 1.day, today], [today - 1.day, today], [today, season.end_date + 1.day]].each do |first, last|
      expect { described_class.new(season:, start_date: first, end_date: last) }.to raise_error(ArgumentError)
    end
    expect(Ingestion::GamesIngestionService).not_to have_received(:new)
  end
end
