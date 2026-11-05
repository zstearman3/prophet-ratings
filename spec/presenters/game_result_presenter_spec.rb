# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GameResultPresenter do
  include_context 'with scoring review evidence'

  it 'shows source result and boxes without linking the replaced participant or changing canonical eligibility', :aggregate_failures do
    pending = Ingestion::Cbbd::ImportObservation.new(row, season).payload.merge(source_status: 'scheduled', source_completed: false,
                                                                                completion_evidence: nil)
    report = Ingestion::GameObservationImporter.new(observation: pending, season:).call
    game = Game.find(report[:game_id])
    payload = Ingestion::Cbbd::ImportObservation.new(row, season).payload.deep_stringify_keys
    payload['away'].merge!('name' => 'Replacement College', 'external_team_id' => '99')
    source = GameObservation.create!(provider: 'cbbd', external_game_id: '1', outcome: 'conflict',
                                     reason: 'participant_or_orientation_conflict', normalized_payload: payload)
    GameIngestionIssue.capture!(season:, observation: source, category: 'participants', game:)
    allow(game).to receive(:current_bet_recommendations).and_return([:stale_recommendation])
    result = described_class.wrap([game]).sole
    expect(result.current_bet_recommendations).to be_empty
    expect(result).to be_completed
    expect(result.away_team_name).to eq('Replacement College')
    expect(result.away_team_score).to eq(64)
    expect(result.away_team_game.team).to be_nil
    expect(result.home_team_game.free_throws_made).to eq(8)
    expect(game.reload).to be_scheduled
  end

  it 'uses ordinary unavailable-result text for an unusable past final without an error marker' do
    game = create(:game, season:, status: :scheduled, start_time: Time.utc(2025, 11, 1, 23), home_team_name: 'Synthetic Home',
                         away_team_name: 'Synthetic Away')
    payload = Ingestion::Cbbd::ImportObservation.new(row, season).payload.deep_stringify_keys
    payload['source_completed'] = false
    payload['home']['score'] = 0
    payload['away']['score'] = 0
    source = GameObservation.create!(provider: 'cbbd', external_game_id: '1', outcome: 'invalid',
                                     reason: 'source not confirmed final', normalized_payload: payload)
    GameIngestionIssue.capture!(season:, observation: source, category: 'missing_result', game:)
    result = described_class.wrap([game]).sole
    expect(result.status_string).to eq('Result unavailable')
    expect(result).not_to be_completed
    expect(result.home_team_score).to be_nil
  end
end
