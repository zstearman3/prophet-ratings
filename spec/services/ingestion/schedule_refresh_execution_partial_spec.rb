# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe Ingestion::ScheduleRefreshExecution do
  let(:date) { Date.new(2025, 11, 1) }
  let(:season) { create(:season, year: 2026, start_date: date, end_date: date + 20.days) }
  let(:run) do
    ScheduleRefreshRun.create!(season:, requested_by: create(:user, :admin), provider: 'cbbd', mode: 'historical',
                               start_date: date, end_date: date, max_requests: 2, retries: 0)
  end
  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/ingestion/cbbd/final.json').read) }
  let(:directory) { Dir.mktmpdir('partial-import') }
  let(:requests) { [] }
  let(:transport) do
    lambda do |uri, _key|
      requests << uri
      { status: 200, headers: {}, body: fixture.fetch(uri.path == '/games' ? 'games' : 'boxes').to_json }
    end
  end
  let(:options) { { api_key: 'synthetic', capture_directory: directory, max_requests: 2, retries: 0, transport: } }

  before do
    allow(Game).to receive(:current_schedule_date).and_return(date + 30.days)
    %w[10 20 30 40].each do |id|
      team = create(:team, school: "Synthetic #{id}")
      create(:team_season, team:, season:)
      TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: id)
    end
    second = fixture['games'].first.deep_dup.merge('id' => 2, 'homeTeamId' => 30, 'awayTeamId' => 40,
                                                   'homeTeam' => 'Other Home', 'awayTeam' => 'Other Away')
    fixture['games'] << second
    fixture['boxes'] += fixture['boxes'].map do |box|
      box.deep_dup.merge('gameId' => 2, 'teamId' => box['teamId'] + 20, 'opponentId' => box['opponentId'] + 20)
    end
    fixture['boxes'][2]['teamStats']['points']['total'] = 999
    fixture['boxes'][3]['opponentStats']['points']['total'] = 999
    allow(ENV).to receive(:fetch).and_call_original
    { 'CBBD_API_KEY' => 'synthetic', 'CBBD_CAPTURE_DIRECTORY' => directory }.each do |key, value|
      allow(ENV).to receive(:fetch).with(key, nil).and_return(value)
    end
    allow(Ingestion::Cbbd::Adapter).to receive(:new).and_wrap_original do |original, **arguments|
      original.call(**arguments, transport:)
    end
  end

  after { FileUtils.remove_entry(directory) }

  it 'commits valid games, retains rejected evidence, and retries the unfinished date without duplicates', :aggregate_failures do
    described_class.new(run).call
    expect(run.reload.status).to eq('incomplete')
    expect(Game.count).to eq(1)
    expect(TeamGame.count).to eq(2)
    expect(GameSyncDate.sole).to have_attributes(status: 'failed', imported_rows: 1)
    day = run.report.fetch('days').sole
    expect(day).to include('imported_rows' => 1, 'changed_rows' => 1, 'status' => 'failed')
    expect(day['rolled_back']).not_to be(true)
    retained = GameObservation.where(id: day.fetch('rejection_observation_ids')).sole
    expect(retained).to have_attributes(accepted: false, game_id: nil, outcome: 'invalid')
    expect(run.rejection_observations.keys).to include(retained.id)
    expect(run.pending_dates).to eq([date.iso8601])
    first_game = Game.sole.id
    fixture['boxes'][2]['teamStats']['points']['total'] = 65
    fixture['boxes'][3]['opponentStats']['points']['total'] = 65
    child = run.create_retry!(run.requested_by)
    described_class.new(child).call
    expect(child.reload.status).to eq('succeeded')
    expect(Game.count).to eq(2)
    expect(Game.exists?(first_game)).to be(true)
    expect(TeamGame.count).to eq(4)
    expect(requests.size).to eq(4)
  end

  it 'rolls back domain writes for incomplete finals while preserving other games', :aggregate_failures do
    fixture['boxes'].reject! { |box| box['gameId'] == 2 }
    described_class.new(run).call
    expect(run.reload.status).to eq('incomplete')
    expect(Game.count).to eq(1)
    expect(TeamGame.count).to eq(2)
    expect(GameExternalIdentity.pluck(:external_id)).to eq(['1'])
    rejected = GameObservation.where(outcome: 'incomplete').sole
    expect(rejected).to have_attributes(accepted: false, game_id: nil)
    expect(run.report.fetch('days').sole['imported_rows']).to eq(1)
  end

  it 'rolls back successful rows and rejection audits when retained progress cannot be saved' do
    allow(run).to receive(:checkpoint).and_raise(IOError, 'private report failure')
    described_class.new(run).call
    expect(run.reload.status).to eq('failed')
    expect([Game.count, TeamGame.count, GameObservation.count]).to eq([0, 0, 0])
    expect(GameSyncDate.where(status: 'completed')).not_to exist
    expect(run.report).to eq({})
  end

  it 'rolls back the entire date on unexpected importer errors' do
    allow(Ingestion::Cbbd::ImportObservation).to receive(:new).and_wrap_original do |original, row, selected_season|
      raise IOError, 'unexpected import failure' if row['source_game_id'] == 2

      original.call(row, selected_season)
    end
    described_class.new(run).call
    expect(run.reload.status).to eq('incomplete')
    expect([Game.count, TeamGame.count, GameObservation.count]).to eq([0, 0, 0])
    expect(run.report.fetch('days').sole['imported_rows'].to_i).to eq(0)
  end

  it 'preserves whole-date rollback for callers that do not opt in' do
    result = Ingestion::GameSyncRun.new(season:, dates: [date], resume: false, provider: 'cbbd', provider_options: options).call
    expect(result[:complete]).to be(false)
    expect(result[:days].sole).to include(rolled_back: true, imported_rows: 0)
    expect([Game.count, TeamGame.count]).to eq([0, 0])
  end
end
