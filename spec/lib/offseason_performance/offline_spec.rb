# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/offline')
require Rails.root.join('script/performance/fixture')

RSpec.describe OffseasonPerformance::Offline do
  let(:transport) { described_class }
  let(:uri) do
    URI('https://api.collegebasketballdata.com/games?season=2025&startDateRange=2024-11-01T04%3A00%3A00.000Z&' \
        'endDateRange=2024-11-02T03%3A59%3A59.999Z')
  end

  it 'returns deterministic synthetic data for exactly the bounded offline request' do
    response = transport.call(uri, 'synthetic-offline-only')
    expect(response[:status]).to eq(200)
    expect(JSON.parse(response[:body]).first).to include('id' => 900_001, 'season' => 2025, 'homeTeam' => 'Synthetic University 021')
  end

  it 'imports a new final through the real normalizer and retains repeated observation evidence' do
    season = create(:season, year: 2025, start_date: '2024-11-01', end_date: '2025-04-10')
    [21, 22].each do |number|
      team = create(:team, school: format('Synthetic University %03d', number))
      create(:team_season, team:, season:)
      TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: (number * 10).to_s)
    end
    game = JSON.parse(transport.call(uri, 'synthetic-offline-only')[:body]).first
    uri.path = '/games/teams'
    boxes = JSON.parse(transport.call(uri, 'synthetic-offline-only')[:body])
    entry = lambda do |raw|
      { 'raw' => raw, 'provenance' => { 'id' => 'offline', 'captured_at' => '2025-06-30T00:00:00Z' } }
    end
    normalized = Ingestion::Cbbd::Normalizer.new(entry.call(game), boxes.map(&entry)).call
    result = Ingestion::Cbbd::ImportObservation.new(normalized, season).call
    expect(result).to include(outcome: 'final', accepted: true)
    expect(Game.find(result.fetch(:game_id))).to have_attributes(status: 'final', home_team_score: 65, away_team_score: 64)
    expect(Ingestion::Cbbd::ImportObservation.new(normalized, season).call).to include(outcome: 'unchanged')
    expect(GameObservation.where(game_id: result.fetch(:game_id)).count).to eq(2)
    expect(GameObservation.where(game_id: result.fetch(:game_id), accepted: true).count).to eq(1)
  end

  it 'rejects unknown paths, bounds and credentials instead of contacting a provider' do
    expect { transport.call(uri, 'unexpected-key') }.to raise_error(ArgumentError, /Unexpected offline/)
    uri.path = '/draft/picks'
    expect { transport.call(uri, 'synthetic-offline-only') }.to raise_error(ArgumentError, /Unexpected offline/)
    uri.path = '/games'
    uri.query = 'season=2025'
    expect { transport.call(uri, 'synthetic-offline-only') }.to raise_error(ArgumentError, /Unexpected offline/)
  end
end
