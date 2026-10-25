# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::ScoringReviewImport do
  include_context 'with scoring review evidence'

  it 'imports the selected reported result with an automatic audit and unchanged original evidence', :aggregate_failures do
    original = observation.attributes.deep_dup
    review = approve
    game = review.game
    expect(game).to have_attributes(status: 'final', home_team_score: 65, away_team_score: 64)
    expect(game.home_team_game).to have_attributes(points: 65, free_throws_made: 8)
    # 55 FGA - 10 ORB + 10 TOV + .475 * 12 FTA = 60.7 possessions.
    expect(game.home_team_game.offensive_rating).to eq(107.084)
    expect(game.away_team_game.defensive_rating).to eq(107.084)
    expect(review).to have_attributes(reason: 'Approved by admin', reviewed_by: admin)
    expect(review.imported_observation).to have_attributes(accepted: true, scoring_review_id: review.id)
    expect(observation.reload.attributes).to eq(original)
    expect { review.update!(choices: {}) }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'lets the admin explicitly choose shooting arithmetic, including a changed winner' do
    game = approve({ 'home' => '63' }).game
    expect(game).to have_attributes(home_team_score: 63, away_team_score: 64, status: 'final')
    expect(game.home_team_game.points).to eq(63)
    expect(game.home_team_game.offensive_rating).to eq(103.789)
  end

  it 'retains approvals across reload and re-finalization but rejects changed stored counts' do
    game = approve.game.reload
    expect { game.finalize }.not_to raise_error
    game.home_team_game.update!(free_throws_made: 9)
    expect { game.reload.finalize }.to raise_error(ProphetRatings::GameFinalizer::MissingDerivedStatsError)
  end

  it 'handles reported points lower than the shooting total' do
    boxes.first['teamStats']['freeThrows']['made'] = 12
    boxes.last['opponentStats']['freeThrows']['made'] = 12
    expect(approve.game.home_team_game).to have_attributes(points: 65, free_throws_made: 12)
  end

  it 'does not create duplicate games or decisions on repeated approval' do
    review = approve
    expect(approve).to eq(review)
    expect([Game.count, GameScoringReview.count]).to eq([1, 1])
    expect { approve({ 'home' => '63' }) }.to raise_error(ArgumentError, /already reviewed/)
  end

  it 'requires explicit confirmation without requiring a typed reason' do
    observation
    expect { approve(confirmed: '0') }.to raise_error(ArgumentError, /confirm/i)
    expect([Game.count, GameScoringReview.count]).to eq([0, 0])
  end

  it 'rejects forged totals' do
    expect { approve({ 'home' => '999' }) }.to raise_error(ArgumentError, /select/i)
    expect(Game.count).to eq(0)
  end

  it 'rejects tied selected final scores' do
    boxes.first['teamStats']['freeThrows']['made'] = 9
    boxes.last['opponentStats']['freeThrows']['made'] = 9
    expect { approve({ 'home' => '64' }) }.to raise_error(ArgumentError, /differ/)
    expect(Game.count).to eq(0)
  end

  it 'keeps unrelated component errors blocking' do
    boxes.first['teamStats']['rebounds']['total'] = 31
    boxes.last['opponentStats']['rebounds']['total'] = 31
    expect { approve }.to raise_error(ArgumentError, /scoring|review|rebounds/i)
    expect([Game.count, GameScoringReview.count]).to eq([0, 0])
  end

  it 'keeps impossible shot attempts blocking' do
    boxes.first['teamStats']['freeThrows']['made'] = 13
    boxes.last['opponentStats']['freeThrows']['made'] = 13
    expect { approve }.to raise_error(ArgumentError)
    expect(Game.count).to eq(0)
  end

  it 'requires complete numeric boxes rather than approving unknown counts' do
    boxes.first['teamStats'].delete('assists')
    boxes.last['opponentStats'].delete('assists')
    expect { approve }.to raise_error(ArgumentError)
    expect(Game.count).to eq(0)
  end

  it 'keeps original period contradictions blocking' do
    source_game['homePeriodPoints'] = [10, 10]
    expect { approve }.to raise_error(ArgumentError)
    expect(Game.count).to eq(0)
  end

  it 'rolls back game, review and identity when finalization fails' do
    observation
    allow(ProphetRatings::GameFinalizer).to receive(:new).and_raise(IOError, 'synthetic failure')
    expect { approve }.to raise_error(IOError)
    expect([Game.count, TeamGame.count, GameExternalIdentity.count, GameScoringReview.count]).to eq([0, 0, 0, 0])
  end

  it 'preserves name-only opponent behavior instead of fabricating rating membership' do
    TeamExternalIdentity.find_by!(provider: 'cbbd', external_id: '20').destroy!
    TeamSeason.joins(:team).find_by!(teams: { school: 'Synthetic Away' }).destroy!
    Team.find_by!(school: 'Synthetic Away').destroy!
    game = approve.game
    expect(game).to be_final_unmatched
    expect(game.home_team_game.points).to eq(65)
    expect(game.away_team_game).to be_nil
    expect(game.possessions).to be_nil
  end

  it 'invalidates an approval after the score of a name-only opponent changes' do
    TeamExternalIdentity.find_by!(provider: 'cbbd', external_id: '20').destroy!
    TeamSeason.joins(:team).find_by!(teams: { school: 'Synthetic Away' }).destroy!
    Team.find_by!(school: 'Synthetic Away').destroy!
    review = approve
    review.game.update!(away_team_score: 62)
    expect(review.matches_game?(review.game.reload)).to be(false)
  end

  it 'completes a compatible existing pending game without duplicating its identity' do
    pending = Ingestion::Cbbd::ImportObservation.new(row, season).payload.deep_dup
    pending.merge!(source_status: 'scheduled', source_completed: false, completion_evidence: nil)
    initial = Ingestion::GameObservationImporter.new(observation: pending, season:).call
    expect(Game.find(initial[:game_id])).to be_scheduled
    expect(approve.game.id).to eq(initial[:game_id])
    expect([Game.count, GameExternalIdentity.count]).to eq([1, 1])
  end

  it 'refuses to overwrite an existing conflicting completed game' do
    observation
    consistent = Ingestion::Cbbd::ImportObservation.new(row, season).payload.deep_dup
    consistent[:home][:stats][:free_throws_made] = 10
    report = Ingestion::GameObservationImporter.new(observation: consistent, season:).call
    game = Game.find(report.fetch(:game_id))
    expect { approve }.to raise_error(ArgumentError, /completed|source facts changed/i)
    expect(game.home_team_game.reload.free_throws_made).to eq(10)
    expect(GameScoringReview.count).to eq(0)
  end
end
