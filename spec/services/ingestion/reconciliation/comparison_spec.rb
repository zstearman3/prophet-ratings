# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::Reconciliation::Comparison do
  include_context 'with synthetic reconciliation'

  it 'reports conservative proposals and exact source denominators without writes' do
    game
    expect { report }.not_to change(GameExternalIdentity, :count)
    expect(report['teams'].pluck('status')).to eq(%w[proposed proposed])
    expect(report['games'].first).to include('status' => 'proposed', 'candidate_ids' => [game.id])
    expect(report['coverage']).to include('source_observations' => 1, 'source_team_ids' => 2)
  end

  it 'uses stable team identities before changed names and aliases' do
    TeamExternalIdentity.associate!(team: teams.first, provider: 'cbbd', external_id: '10')
    observation['home']['source_name'] = 'Changed Name'
    expect(report['teams'].first).to include('status' => 'mapped', 'mapped_id' => teams.first.id)
  end

  it 'unions canonical and alias matches instead of choosing the first' do
    create(:team_alias, team: teams.last, value: teams.first.school)
    expect(report['teams'].first).to include('status' => 'ambiguous', 'candidate_ids' => teams.map(&:id).sort)
  end

  it 'does not create memberships for lower-division or unknown source teams' do
    game
    TeamSeason.where(team: teams.first).destroy_all
    expect(report['teams'].first).to include('status' => 'conflicting', 'eligible_ids' => [])
    expect(report['games'].first['status']).to eq('conflicting')
    observation['home']['source_name'] = 'Unknown synthetic school'
    expect(report['teams'].first['status']).to eq('unmatched')
  end

  it 'preserves opaque IDs and exposes source label collisions' do
    observation['home']['source_team_id'] = '0010'
    observation['away']['source_name'] = observation['home']['source_name']
    expect(report['teams'].pluck('external_id')).to include('0010')
    expect(report['teams'].pluck('status')).to eq(%w[conflicting conflicting])
  end

  it 'retains duplicate source observations and incomplete acquisition denominators' do
    replay['observations'] << observation.deep_dup
    replay['complete'] = false
    result = report
    expect(result['games'].first).to include('status' => 'conflicting', 'occurrences' => 2)
    expect(result['coverage']).to include('source_observations' => 2, 'source_game_ids' => 1, 'source_team_occurrences' => 4,
                                          'acquisition_complete' => false)
  end

  it 'retains malformed and out-of-window source evidence as conflicts' do
    observation['schedule_date'] = '2025-11-03'
    expect(report['games'].first['conflicts']).to include('outside_requested_window')
    observation['schedule_date'] = '2025-11-99'
    expect(report['games'].first['conflicts']).to include('invalid_schedule_date')
  end

  it 'retains stable game ownership despite a closer label candidate' do
    original = game
    GameExternalIdentity.associate!(game: original, provider: 'cbbd', external_id: '1')
    create(:game, season:, start_time: '2025-11-02T23:00:00Z', home_team_name: teams.first.school,
                  away_team_name: teams.last.school)
    expect(report['games'].first).to include('status' => 'mapped', 'candidate_ids' => [original.id])
  end

  it 'reports reversed nonneutral participants for review, and aligns neutral proposals' do
    game.update!(home_team_name: teams.last.school, away_team_name: teams.first.school)
    expect(report['games'].first['status']).to eq('review_required')
    observation['venue']['certainty'] = 'neutral'
    expect(report['games'].first).to include('status' => 'proposed')
    expect(report['games'].first['candidates'].first['reversed']).to be(true)
  end

  it 'retains shifted legacy dates and different-date possible reschedules' do
    game.update!(start_time: '2025-11-01T00:00:00Z')
    expect(report['games'].first['candidates'].first['rules']).to include('legacy_date_shift', 'possible_reschedule')
    game.update!(start_time: '2025-12-01T23:00:00Z')
    expect(report['games'].first['status']).to eq('review_required')
  end

  it 'does not collapse multiple local games or possible same-day doubleheaders' do
    original = game
    other = build(:game, season:, start_time: '2025-11-01T20:00:00Z', home_team_name: teams.first.school,
                         away_team_name: teams.last.school)
    other.save!(validate: false)
    expect(report['games'].first).to include('status' => 'ambiguous', 'candidate_ids' => [original.id, other.id])
    expect(report['local_duplicates'].first['local_ids']).to eq([original.id, other.id])
  end

  it 'invalidates fingerprints on aliases, memberships, new candidates, manual venue and raw stats' do
    original = report['fingerprint']
    create(:team_alias, team: teams.first, value: 'New alias')
    expect(report['fingerprint']).not_to eq(original)
    previous = report['fingerprint']
    game.update!(venue_confidence: 'manual')
    expect(report['fingerprint']).not_to eq(previous)
    previous = report['fingerprint']
    create(:team_game, game:, team: teams.first, team_season: teams.first.team_seasons.find_by!(season:), home: true, points: 3)
    expect(report['fingerprint']).not_to eq(previous)
  end

  it 'preserves all persisted canonical state during comparison and shadow' do
    snapshot = create(:team_rating_snapshot, team_season: teams.first.team_seasons.find_by!(season:))
    create(:prediction, game:, home_team_snapshot: snapshot, away_team_snapshot: snapshot,
                        ratings_config_version: snapshot.ratings_config_version)
    GameObservation.create!(game:, outcome: 'synthetic', normalized_payload: observation)
    models = [Game, TeamGame, Prediction, TeamRatingSnapshot, GameObservation, Team, TeamSeason]
    before = models.map { |model| model.order(:id).map(&:attributes) }
    report
    expect(models.map { |model| model.order(:id).map(&:attributes) }).to eq(before)
  end

  it 'keeps uncertain side alignment out of shadow even when only one game matches' do
    create(:team_alias, team: teams.last, value: teams.first.school)
    create(:team_alias, team: teams.first, value: teams.last.school)
    game
    expect(report['games'].first['status']).to eq('ambiguous')
    expect(report['shadow']['games_compared']).to eq(0)
  end

  it 'does not group unrelated unknown-label games as duplicates' do
    create(:game, season:, start_time: '2025-11-01T23:00:00Z', home_team_name: 'Unknown one', away_team_name: 'Unknown two')
    create(:game, season:, start_time: '2025-11-01T23:00:00Z', home_team_name: 'Unknown three', away_team_name: 'Unknown four')
    expect(report['local_duplicates']).to eq([])
  end
end
