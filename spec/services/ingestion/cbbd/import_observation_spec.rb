# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::Cbbd::ImportObservation do
  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/ingestion/cbbd/final.json').read) }
  let(:source_game) { fixture.fetch('games').first }
  let(:boxes) { fixture.fetch('boxes') }
  let(:season) { create(:season, year: 2026, start_date: '2025-11-01', end_date: '2026-04-10') }
  let(:team) { create(:team, school: source_game.fetch('homeTeam')) }

  before do
    create(:team_season, team:, season:)
    TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: source_game.fetch('homeTeamId').to_s)
  end

  def entry(raw, index)
    { 'raw' => raw, 'provenance' => { 'id' => "synthetic-#{index}", 'sha256' => 'synthetic', 'row_index' => index,
                                      'captured_at' => '2025-11-02T12:00:00Z' } }
  end

  def ingest
    normalized = Ingestion::Cbbd::Normalizer.new(entry(source_game, 0),
                                                 boxes.each_with_index.map { |box, index| entry(box, index + 1) }).call
    described_class.new(normalized, season).call
  end

  it 'accepts a score-only final with absent opponent boxes as not applicable to model inputs' do
    boxes.clear
    result = ingest
    expect(result).to include(outcome: 'final', final_box: 'not_applicable', accepted: true)
    expect(Game.find(result.fetch(:game_id))).to have_attributes(status: 'final_unmatched', home_team_score: 65, away_team_score: 64)
    expect(ingest).to include(outcome: 'unchanged', final_box: 'not_applicable')
  end

  it 'does not turn malformed supplied counts into acceptable missing data' do
    boxes.last['teamStats']['assists'] = -1
    boxes.each { |box| box.delete('opponentStats') }
    expect(ingest).to include(outcome: 'invalid', final_box: 'invalid')
    expect(Game.count).to eq(0)
    expect(GameObservation.last.raw_payload.dig('away', 'stats', 'assists', 'raw')).to eq(-1)
  end

  it 'holds participant metadata conflicts even if one box is absent' do
    boxes.pop
    boxes.first['opponentId'] = 999
    expect(ingest).to include(outcome: 'invalid', final_box: 'invalid')
    expect(Game.count).to eq(0)
  end

  it 'holds contradictory final status evidence rather than creating an unknown fixture' do
    boxes.first['status'] = 'in_progress'
    expect(ingest).to include(outcome: 'invalid', final_box: 'invalid')
    expect(Game.count).to eq(0)
  end

  it 'holds period scoring contradictions even when raw boxes are absent' do
    boxes.clear
    source_game['awayPeriodPoints'] = [20, 20]
    expect(ingest).to include(outcome: 'invalid', final_box: 'invalid')
    expect(Game.count).to eq(0)
  end
end
