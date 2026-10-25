# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe Ingestion::ScoringReviewReplay do
  include_context 'with scoring review evidence'

  it 'reuses a decision when only capture time and IDs change', :aggregate_failures do
    review = approve
    recaptured = row.deep_dup
    recaptured['provenance'].each { |capture| capture.merge!('id' => 'new-capture', 'captured_at' => '2025-11-03T12:00:00Z') }
    report = Ingestion::Cbbd::ImportObservation.new(recaptured, season).call
    expect(report).to include(outcome: 'unchanged', game_id: review.game.id, applied: true, final_box: 'complete')
    expect([Game.count, GameScoringReview.count]).to eq([1, 1])
    expect(GameObservation.where(scoring_review: review, accepted: true).count).to eq(1)
    expect(review.game.home_team_game.points).to eq(65)
  end

  it 'holds changed source facts without replacing the reviewed game' do
    game = approve.game
    changed = row.deep_dup
    changed['home']['stats']['turnovers']['value'] = 11
    result = Ingestion::Cbbd::ImportObservation.new(changed, season).call
    expect(result).to include(outcome: 'conflict', reason: 'reviewed_source_changed')
    expect(game.home_team_game.reload.turnovers).to eq(10)
  end

  it 'holds even numerically valid newer source changes to a reviewed result' do
    game = approve.game
    boxes.first['teamStats']['freeThrows']['made'] = 10
    boxes.last['opponentStats']['freeThrows']['made'] = 10
    corrected = Ingestion::Cbbd::Normalizer.new(source_entry(source_game, 0),
                                                boxes.each_with_index.map { |box, index| source_entry(box, index + 1) }).call
    corrected['source_updated_at'] = '2025-11-05T12:00:00Z'
    expect(Ingestion::Cbbd::ImportObservation.new(corrected, season).call).to include(outcome: 'conflict')
    expect(game.home_team_game.reload.free_throws_made).to eq(8)
  end

  it 'does not reuse an approval after stored box inputs change' do
    game = approve.game
    game.home_team_game.update!(turnovers: 11)
    expect(Ingestion::Cbbd::ImportObservation.new(row, season).call).to include(outcome: 'conflict')
    expect(game.home_team_game.reload.turnovers).to eq(11)
  end

  it 'does not accept an old rejection once different source facts have been retained' do
    observation
    changed = row.deep_dup
    changed['home']['stats']['turnovers']['value'] = 11
    Ingestion::Cbbd::ImportObservation.new(changed, season).call
    expect { approve }.to raise_error(ArgumentError, /source.*changed|fresh/i)
    expect(Game.count).to eq(0)
  end

  it 'does not reuse approval after a source identity has been superseded' do
    approve
    old = GameExternalIdentity.find_by!(provider: 'cbbd', external_id: '1')
    old.supersede!(external_id: 'replacement')
    expect(Ingestion::Cbbd::ImportObservation.new(row, season).call).to include(outcome: 'superseded')
  end

  it 'finishes the previously incomplete date on an unchanged-source retry without duplicate games' do
    game = approve.game
    Dir.mktmpdir do |directory|
      allow(ENV).to receive(:fetch).and_call_original
      { 'CBBD_API_KEY' => 'synthetic', 'CBBD_CAPTURE_DIRECTORY' => directory }.each do |key, value|
        allow(ENV).to receive(:fetch).with(key, nil).and_return(value)
      end
      acquisition = { 'complete' => true, 'acquisition' => { 'complete' => true, 'attempts' => 2 }, 'observations' => [row] }
      allow(Ingestion::Cbbd::Adapter).to receive(:new).and_return(instance_double(Ingestion::Cbbd::Adapter, call: acquisition))
      child = run.create_retry!(admin)
      Ingestion::ScheduleRefreshExecution.new(child).call
      expect(child.reload.status).to eq('succeeded')
      expect(child.pending_dates).to be_empty
      expect(GameSyncDate.sole).to have_attributes(status: 'completed')
      expect(Game.pluck(:id)).to eq([game.id])
    end
  end

  it 'holds after a previously name-only opponent gains a membership' do
    TeamExternalIdentity.find_by!(provider: 'cbbd', external_id: '20').destroy!
    TeamSeason.joins(:team).find_by!(teams: { school: 'Synthetic Away' }).destroy!
    team = Team.find_by!(school: 'Synthetic Away')
    team.destroy!
    game = approve.game
    replacement = create(:team, school: 'Synthetic Away')
    create(:team_season, team: replacement, season:)
    TeamExternalIdentity.associate!(team: replacement, provider: 'cbbd', external_id: '20')
    expect(Ingestion::Cbbd::ImportObservation.new(row, season).call).to include(outcome: 'conflict')
    expect(game.reload).to be_final_unmatched
    expect(game.away_team_game).to be_nil
  end

  it 'holds after stored participant IDs change without altering the source facts' do
    game = approve.game
    replacement = create(:team_season, season:)
    game.home_team_game.update!(team: replacement.team, team_season: replacement)
    expect(Ingestion::Cbbd::ImportObservation.new(row, season).call).to include(outcome: 'conflict')
    expect(game.home_team_game.reload.team_season).to eq(replacement)
  end
end
