# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::GameIssueResolution do
  include_context 'with scoring review evidence'

  def resolve(issue, action, values = {}, fingerprint = issue.comparison_fingerprint)
    Ingestion::GameIssueResolution.new(issue:, user: admin, action:, values:, fingerprint:).call
  end

  it 'acknowledges a warning privately and applies a supplied correction to an already final game', :aggregate_failures do
    Ingestion::Cbbd::ImportObservation.new(row, season).call
    issue = GameIngestionIssue.sole
    decision = resolve(issue, 'acknowledge')
    expect(decision.message).to eq('Acknowledged by admin')
    expect(issue.reload.state).to eq('resolved')
    expect(issue.game.home_team_score).to eq(65)
    resolve(issue, 'select_scores', { 'home' => '63' })
    expect(issue.game.reload).to have_attributes(status: 'final', home_team_score: 63)
    expect(issue.game.home_team_game.points).to eq(63)
    expect(Ingestion::Cbbd::ImportObservation.new(row, season).call).to include(outcome: 'unchanged')
    expect(issue.game.reload.home_team_score).to eq(63)
  end

  it 'selects an untracked replacement opponent and imports retained stats without fetching again', :aggregate_failures do
    boxes.first['teamStats']['freeThrows']['made'] = 10
    boxes.last['opponentStats']['freeThrows']['made'] = 10
    pending = Ingestion::Cbbd::ImportObservation.new(row, season).payload.merge(source_status: 'scheduled', source_completed: false,
                                                                                completion_evidence: nil)
    initial = Ingestion::GameObservationImporter.new(observation: pending, season:).call
    changed = row.deep_dup
    changed['home']['stats']['points']['value'] = 63
    changed['reasons'] = ['points disagree with score', 'points: component mismatch']
    changed['away'].merge!('source_name' => 'Replacement College', 'source_team_id' => '99')
    report = Ingestion::HistoricalSyncObservation.new(changed, season).call
    issue = GameIngestionIssue.where(id: report[:issue_ids], category: 'participants').sole
    expect(issue.category).to eq('participants')
    expect(issue.game.id).to eq(initial[:game_id])
    home_id = issue.game.home_team.id
    fingerprint = issue.comparison_fingerprint
    values = { 'home' => home_id.to_s, 'away' => 'source' }
    first = resolve(issue, 'select_participants', values, fingerprint)
    game = issue.game.reload
    expect(game).to have_attributes(status: 'final_unmatched', away_team_name: 'Replacement College', away_team_score: 64)
    expect(game.home_team_game).to have_attributes(points: 65, free_throws_made: 10)
    expect(game.away_team_game).to be_nil
    expect(resolve(issue, 'select_participants', values, fingerprint)).to eq(first)
    expect(Ingestion::Cbbd::ImportObservation.new(changed, season).call).to include(outcome: 'unchanged')
    expect(TeamSeason.count).to eq(2)
  end

  it 'rejects stale comparisons and forged totals without recording a decision' do
    Ingestion::Cbbd::ImportObservation.new(row, season).call
    issue = GameIngestionIssue.sole
    expect { resolve(issue, 'select_scores', { 'home' => '999' }) }.to raise_error(ArgumentError)
    expect { resolve(issue, 'acknowledge', {}, 'stale') }.to raise_error(ArgumentError, /changed|reload/i)
    expect(issue.decisions.count).to eq(0)
    expect(issue.game.reload.home_team_score).to eq(65)
  end

  it 'does not acknowledge changed evidence that has not been applied, while preserving the old scoring exception' do
    Ingestion::Cbbd::ImportObservation.new(row, season).call
    issue = GameIngestionIssue.sole
    resolve(issue, 'acknowledge')
    changed = row.deep_dup
    changed['home']['stats']['turnovers']['value'] = 11
    Ingestion::HistoricalSyncObservation.new(changed, season).call
    issue.reload
    expect(issue.state).to eq('open')
    expect { resolve(issue, 'acknowledge') }.to raise_error(ArgumentError, /import|evidence|changed/)
    expect { issue.game.reload.finalize }.not_to raise_error
  end

  it 'accepts an explicit completed-source correction without relaxing ordinary freshness checks' do
    row['home']['stats']['points']['value'] = 63
    Ingestion::HistoricalSyncObservation.new(row, season).call
    changed = row.deep_dup
    changed['home']['stats']['turnovers']['value'] = 11
    report = Ingestion::HistoricalSyncObservation.new(changed, season).call
    issue = GameIngestionIssue.find(report[:issue_ids].last)
    expect(issue.category).to eq('source_revision')
    resolve(issue, 'accept_source')
    expect(issue.game.home_team_game.reload).to have_attributes(turnovers: 11, points: 65)
    expect { issue.game.reload.finalize }.not_to raise_error
  end

  it 'records a valid participant choice but keeps missing-box results open without attributing partial stats' do
    boxes.first['teamStats']['freeThrows']['made'] = 10
    boxes.last['opponentStats']['freeThrows']['made'] = 10
    pending = Ingestion::Cbbd::ImportObservation.new(row, season).payload.merge(source_status: 'scheduled', source_completed: false,
                                                                                completion_evidence: nil)
    initial = Ingestion::GameObservationImporter.new(observation: pending, season:).call
    replacement = create(:team, school: 'Replacement College')
    create(:team_season, team: replacement, season:)
    changed = row.deep_dup
    changed['away'].merge!('source_name' => replacement.school, 'source_team_id' => '99')
    changed['away']['stats']['assists'].merge!('value' => nil, 'reason' => 'source_null')
    changed['reasons'] = ['assists: source_null']
    report = Ingestion::HistoricalSyncObservation.new(changed, season).call
    issue = GameIngestionIssue.find(report[:issue_ids].sole)
    values = { 'home' => issue.game.home_team.id.to_s, 'away' => replacement.id.to_s }
    decision = resolve(issue, 'select_participants', values)
    expect(decision.values).to eq(values)
    expect(issue.reload.state).to eq('open')
    expect(Game.find(initial[:game_id])).to be_scheduled
    expect(issue.game.away_team).not_to eq(replacement)
  end

  it 'lets an admin retain the existing team after a source ID changes without creating global mappings' do
    boxes.first['teamStats']['freeThrows']['made'] = 10
    boxes.last['opponentStats']['freeThrows']['made'] = 10
    pending = Ingestion::Cbbd::ImportObservation.new(row, season).payload.merge(source_status: 'scheduled', source_completed: false,
                                                                                completion_evidence: nil)
    initial = Ingestion::GameObservationImporter.new(observation: pending, season:).call
    changed = row.deep_dup
    changed['away']['source_team_id'] = '99'
    report = Ingestion::HistoricalSyncObservation.new(changed, season).call
    issue = GameIngestionIssue.find(report[:issue_ids].sole)
    values = { 'home' => issue.game.home_team.id.to_s, 'away' => issue.game.away_team.id.to_s }
    resolve(issue, 'select_participants', values)
    expect(Game.find(initial[:game_id])).to be_final
    expect(TeamExternalIdentity.count).to eq(2)
    expect(Ingestion::HistoricalSyncObservation.new(changed, season).call).to include(outcome: 'unchanged')
    expect(issue.reload.state).to eq('resolved')
  end
end
