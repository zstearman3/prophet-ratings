# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::ScoringDiscrepancyImport do
  include_context 'with scoring review evidence'

  def import
    Ingestion::Cbbd::ImportObservation.new(row, season).call
  end

  it 'uses reported scores immediately, retains shooting evidence and survives re-finalization', :aggregate_failures do
    report = import
    expect(report).to include(outcome: 'final', accepted: true)
    game = Game.find(report[:game_id])
    expect(game).to have_attributes(status: 'final', home_team_score: 65, away_team_score: 64)
    expect(game.home_team_game).to have_attributes(points: 65, free_throws_made: 8)
    expect(game.home_team_game.offensive_rating).to eq(107.084)
    issue = GameIngestionIssue.sole
    expect(issue).to have_attributes(category: 'scoring', state: 'open', game_id: game.id)
    expect(issue.original_observation.raw_payload.dig('home', 'stats', 'free_throws_made', 'value')).to eq(8)
    expect(GameScoringReview.count).to eq(0)
    expect { game.reload.finalize }.not_to raise_error
    expect(import).to include(outcome: 'unchanged')
    expect(GameIngestionIssue.count).to eq(1)
    game.home_team_game.update!(free_throws_made: 7)
    expect { game.reload.finalize }.to raise_error(ProphetRatings::GameFinalizer::MissingDerivedStatsError)
  end

  it 'preserves name-only finals without creating rating membership' do
    TeamExternalIdentity.find_by!(provider: 'cbbd', external_id: '20').destroy!
    TeamSeason.joins(:team).find_by!(teams: { school: 'Synthetic Away' }).destroy!
    Team.find_by!(school: 'Synthetic Away').destroy!
    report = import
    game = Game.find(report[:game_id])
    expect(game).to be_final_unmatched
    expect(game.home_team_game.points).to eq(65)
    expect(game.away_team_game).to be_nil
    expect(game.possessions).to be_nil
  end

  it 'closes a scoring issue when a newer clean source result is imported' do
    row['source_updated_at'] = '2025-11-02T12:00:00Z'
    Ingestion::HistoricalSyncObservation.new(row, season).call
    issue = GameIngestionIssue.sole
    corrected = row.deep_dup
    corrected['source_updated_at'] = '2025-11-02T13:00:00Z'
    corrected['home']['stats']['free_throws_made']['value'] = 10
    corrected['reasons'] = []
    expect(Ingestion::HistoricalSyncObservation.new(corrected, season).call).to include(accepted: true)
    expect(issue.reload.state).to eq('resolved')
    expect(issue.game.home_team_game.reload.free_throws_made).to eq(10)
  end

  it 'closes a scoring issue after explicit approval of a clean source correction' do
    Ingestion::HistoricalSyncObservation.new(row, season).call
    scoring_issue = GameIngestionIssue.sole
    corrected = row.deep_dup
    corrected['home']['stats']['free_throws_made']['value'] = 10
    corrected['reasons'] = []
    report = Ingestion::HistoricalSyncObservation.new(corrected, season).call
    revision = GameIngestionIssue.find(report[:issue_ids].sole)
    Ingestion::GameIssueResolution.new(issue: revision, user: admin, action: 'accept_source', values: {},
                                       fingerprint: revision.comparison_fingerprint).call
    expect(scoring_issue.reload.state).to eq('resolved')
  end

  it 'keeps other invalid arithmetic held rather than treating it as a warning' do
    boxes.first['teamStats']['rebounds']['total'] = 31
    boxes.last['opponentStats']['rebounds']['total'] = 31
    expect(import).to include(outcome: 'invalid', accepted: false)
    expect(Game.count).to eq(0)
  end
end
