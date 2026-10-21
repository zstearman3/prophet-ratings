# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::GameObservationImporter do
  let(:season) { Season.create!(year: 2025, start_date: '2024-11-01', end_date: '2025-04-10', name: '2024-25') }
  let(:home_team) { Team.create!(school: 'Home School', nickname: 'Home', slug: 'home', url: 'http://home.com') }
  let(:away_team) { Team.create!(school: 'Away School', nickname: 'Away', slug: 'away', url: 'http://away.com') }
  let(:home_team_season) { TeamSeason.create!(team: home_team, season:) }
  let(:away_team_season) { TeamSeason.create!(team: away_team, season:) }
  let(:home_alias) { TeamAlias.create!(team: home_team, value: home_team.school, source: 'sports_reference') }
  let(:away_alias) { TeamAlias.create!(team: away_team, value: away_team.school, source: 'sports_reference') }
  let(:date) { Date.new(2025, 1, 1) }

  let(:home_team_stats) do
    {
      minutes: 200,
      field_goals_made: 35,
      field_goals_attempted: 68,
      two_pt_made: 24,
      two_pt_attempted: 40,
      three_pt_made: 11,
      three_pt_attempted: 28,
      free_throws_made: 19,
      free_throws_attempted: 24,
      offensive_rebounds: 9,
      defensive_rebounds: 26,
      rebounds: 35,
      assists: 16,
      steals: 7,
      blocks: 4,
      turnovers: 11,
      fouls: 17,
      points: 100
    }
  end

  let(:away_team_stats) do
    {
      minutes: 200,
      field_goals_made: 31,
      field_goals_attempted: 65,
      two_pt_made: 21,
      two_pt_attempted: 39,
      three_pt_made: 10,
      three_pt_attempted: 26,
      free_throws_made: 18,
      free_throws_attempted: 22,
      offensive_rebounds: 10,
      defensive_rebounds: 24,
      rebounds: 34,
      assists: 14,
      steals: 6,
      blocks: 3,
      turnovers: 12,
      fouls: 19,
      points: 90
    }
  end

  let(:canonical_payload) do
    { contract_version: 'ingestion-v1', semantic_profile: 'official-team-totals-v1', provider: 'synthetic',
      external_game_id: '001', season_year: season.year, schedule_date: date.iso8601,
      source_status: 'final', source_completed: true, completion_evidence: 'synthetic-final',
      captured_at: '2025-01-02T12:00:00Z', source_updated_at: '2025-01-02T11:00:00Z',
      source_url: 'https://example.test/001', adapter_revision: 'test-1', duration_minutes: 40,
      home: { name: home_team.school, score: 100, stats: home_team_stats },
      away: { name: away_team.school, score: 90, stats: away_team_stats } }
  end

  let(:payload) { canonical_payload }

  before do
    home_team_season
    away_team_season
  end

  def ingest(values = payload)
    described_class.new(observation: values, season:).call
  end

  def incomplete_participant_game(status, stored_home_name)
    game = Game.find(ingest.fetch(:game_id))
    version = create(:ratings_config_version)
    snapshots = [home_team_season, away_team_season].map do |membership|
      create(:team_rating_snapshot, team_season: membership, ratings_config_version: version, snapshot_date: date - 1)
    end
    create(:prediction, game:, ratings_config_version: version, home_team_snapshot: snapshots.first,
                        away_team_snapshot: snapshots.last, home_offensive_efficiency: 110, away_offensive_efficiency: 100,
                        home_defensive_efficiency: 100, away_defensive_efficiency: 110, pace: 70)
    game.home_team_game.destroy!
    game.update!(status:, home_team_name: stored_home_name)
    game.reload
  end

  def participant_domain_state(game)
    [game.reload.attributes, TeamGame.where(game:).order(:id).map(&:attributes),
     Prediction.where(game:).order(:id).map(&:attributes), GameExternalIdentity.where(game:).order(:id).map(&:attributes),
     GameObservation.where(game:, accepted: true).order(:id).map(&:attributes)]
  end

  shared_examples 'canonical persistence' do
    it 'creates one strictly finalized game, sides and external identity atomically' do
      report = ingest
      expect(report).to include(outcome: 'final', accepted: true)
      game = Game.find(report[:game_id])
      expect(game).to have_attributes(status: 'final', minutes: 40, possessions: 79.5)
      expect(GameExternalIdentity.find_by!(provider: payload[:provider], external_id: payload[:external_game_id]).game).to eq(game)
      expect(TeamGame.where(game:).count).to eq(2)
    end

    it 'does not touch canonical timestamps or provenance head for repeat observations' do
      original = ingest
      game = Game.find(original[:game_id])
      before = [game.attributes, game.home_team_game.attributes, game.away_team_game.attributes]
      expect(ingest).to include(outcome: 'unchanged', accepted: false)
      expect([game.reload.attributes, game.home_team_game.reload.attributes, game.away_team_game.reload.attributes]).to eq(before)
      expect(GameObservation.where(game:, accepted: true).count).to eq(1)
    end

    it 'accepts ordered same-profile corrections and recalculates actual values' do
      original = ingest
      corrected = payload.deep_merge(source_updated_at: '2025-01-03T11:00:00Z',
                                     home: { score: 102,
                                             stats: { points: 102, two_pt_made: 25, field_goals_made: 36 } })
      expect(ingest(corrected)).to include(outcome: 'final', game_id: original[:game_id])
      expect(Game.find(original[:game_id]).home_team_game.offensive_efficiency).to be_within(0.1).of(125.307)
    end

    it 'holds changed final values when source ordering is unknown' do
      original = ingest
      corrected = payload.deep_merge(source_updated_at: nil,
                                     home: { score: 102,
                                             stats: { points: 102, two_pt_made: 25, field_goals_made: 36 } })
      expect(ingest(corrected)).to include(outcome: 'conflict', reason: 'unknown_source_freshness')
      expect(Game.find(original[:game_id]).home_team_score).to eq(100)
    end

    it 'rolls back malformed final domain writes and retains rejection evidence' do
      bad = payload.deep_merge(home: { stats: { points: 101 } })
      expect { expect(ingest(bad)).to include(outcome: 'invalid') }.not_to change(Game, :count)
      expect(TeamGame.count).to eq(0)
      expect(GameExternalIdentity.count).to eq(0)
      expect(GameObservation.last).to have_attributes(outcome: 'invalid', accepted: false, game_id: nil)
    end

    it 'keeps complete live observations nonfinal' do
      expect(ingest(payload.merge(source_status: 'live', source_completed: false))).to include(outcome: 'live')
      expect(Game.last).to be_scheduled
      expect(Game.last.possessions).to be_nil
      expect(Game.last.home_team_game.points).to be_nil
    end

    it 'retains incomplete finals without synthesizing missing statistics' do
      expect(ingest(payload.deep_merge(home: { stats: { turnovers: nil } }))).to include(outcome: 'incomplete')
      expect(Game.last).to be_scheduled
    end

    it 'holds ambiguous participant aliases without domain writes' do
      other = create(:team, school: 'Another school')
      create(:team_alias, team: other, value: home_team.school, source: 'synthetic-review')
      expect(ingest).to include(outcome: 'ambiguous', unmatched: [home_team.school], accepted: false)
      expect(Game.count).to eq(0)
      expect(TeamGame.count).to eq(0)
      expect(GameExternalIdentity.count).to eq(0)
    end

    it 'resolves existing source identities across label and date changes' do
      original = ingest
      TeamExternalIdentity.associate!(team: home_team, provider: payload[:provider], external_id: 'home')
      TeamExternalIdentity.associate!(team: away_team, provider: payload[:provider], external_id: 'away')
      changed = payload.deep_merge(schedule_date: '2025-01-02', source_updated_at: '2025-01-03T11:00:00Z',
                                   home: { name: 'Renamed Home', external_team_id: 'home' },
                                   away: { name: 'Renamed Away', external_team_id: 'away' })
      expect(ingest(changed)).to include(outcome: 'final', game_id: original[:game_id])
      expect(Game.count).to eq(1)
      expect(Game.last).to have_attributes(home_team_name: 'Renamed Home', away_team_name: 'Renamed Away')
    end

    %w[scheduled final_unmatched].each do |stored_status|
      it "holds a different known stored participant with a missing side on #{stored_status}" do
        other = create(:team, school: 'Stored Different Home')
        game = incomplete_participant_game(stored_status, other.school)
        GameExternalIdentity.where(game:).delete_all # Legacy URL bootstrap has no durable source mapping yet.
        before = participant_domain_state(game)
        result = ingest(payload.merge(source_updated_at: '2025-01-03T12:00:00Z'))
        expect(result).to include(outcome: 'conflict', reason: 'participant_or_orientation_conflict', accepted: false)
        expect(participant_domain_state(game)).to eq(before)
      end

      it "holds ambiguous stored participant labels with a missing side on #{stored_status}" do
        other = create(:team, school: 'Stored Ambiguous Home')
        create(:team_alias, team: home_team, value: 'Historic ambiguous label', source: 'first-reviewed')
        create(:team_alias, team: other, value: 'Historic ambiguous label', source: 'second-reviewed')
        game = incomplete_participant_game(stored_status, 'Historic ambiguous label')
        before = participant_domain_state(game)
        result = ingest(payload.merge(source_updated_at: '2025-01-03T12:00:00Z'))
        expect(result).to include(outcome: 'ambiguous', reason: 'ambiguous_stored_participant', accepted: false)
        expect(participant_domain_state(game)).to eq(before)
      end

      it "holds reversed stored orientation with both sides missing on #{stored_status}" do
        game = incomplete_participant_game(stored_status, away_team.school)
        game.away_team_game.destroy!
        game.update!(away_team_name: home_team.school)
        before = participant_domain_state(game)
        result = ingest(payload.merge(source_updated_at: '2025-01-03T12:00:00Z'))
        expect(result).to include(outcome: 'conflict', reason: 'participant_or_orientation_conflict', accepted: false)
        expect(participant_domain_state(game)).to eq(before)
      end

      it "keeps an existing side authoritative over a conflicting stored label on #{stored_status}" do
        original = ingest
        game = Game.find(original[:game_id])
        other = create(:team, school: 'Outdated label evidence')
        game.update!(status: stored_status, home_team_name: other.school)
        home_side_id = game.home_team_game.id
        expect(ingest(payload.merge(source_updated_at: '2025-01-03T12:00:00Z'))).to include(outcome: 'final', game_id: game.id)
        expect(game.reload.home_team_game).to have_attributes(id: home_side_id, team_id: home_team.id)
      end

      it "permits a genuine unknown-label participant resolution on #{stored_status}" do
        game = incomplete_participant_game(stored_status, 'Unmapped historic label')
        prediction = game.predictions.first
        forecast = prediction.attributes.except('updated_at', *Prediction.column_names.grep(/_error$/))
        expect(ingest(payload.merge(source_updated_at: '2025-01-03T12:00:00Z'))).to include(outcome: 'final', game_id: game.id)
        expect(game.reload.home_team_game.team).to eq(home_team)
        expect(prediction.reload.attributes.except('updated_at', *Prediction.column_names.grep(/_error$/))).to eq(forecast)
      end

      it "permits a reviewed stored alias resolving to the incoming team on #{stored_status}" do
        game = incomplete_participant_game(stored_status, 'Reviewed historic label')
        create(:team_alias, team: home_team, value: 'Reviewed historic label', source: 'reviewed-mapping')
        expect(ingest(payload.merge(source_updated_at: '2025-01-03T12:00:00Z'))).to include(outcome: 'final', game_id: game.id)
        expect(game.reload.home_team_game.team).to eq(home_team)
      end
    end

    it 'does not fall back to labels for supplied unmapped team IDs' do
      expect do
        expect(ingest(payload.deep_merge(home: { external_team_id: 'missing' }))).to include(outcome: 'unmatched')
      end.not_to change(Game, :count)
    end

    it 'requires a stable source identity' do
      expect do
        expect(ingest(payload.merge(external_game_id: nil))).to include(reason: 'missing_stable_game_identity')
      end.not_to change(Game, :count)
    end

    it 'holds stale revisions and superseded source identities' do
      original = ingest
      older = payload.deep_merge(source_updated_at: '2025-01-01T11:00:00Z',
                                 home: { score: 102, stats: { points: 102, two_pt_made: 25, field_goals_made: 36 } })
      expect(ingest(older)).to include(outcome: 'stale')
      game = Game.find(original[:game_id])
      GameExternalIdentity.find_by!(game:, provider: payload[:provider]).supersede!(external_id: 'replacement')
      expect(ingest).to include(outcome: 'superseded')
      expect(game.reload.home_team_score).to eq(100)
    end

    it 'keeps identical alternate profiles from relabeling accepted provenance' do
      original = ingest
      alternate = payload[:semantic_profile] == 'official-team-totals-v1' ? 'sports-reference-legacy-v1' : 'official-team-totals-v1'
      expect(ingest(payload.merge(semantic_profile: alternate))).to include(outcome: 'unchanged', accepted: false)
      accepted = GameObservation.where(game_id: original[:game_id], accepted: true)
      expect(accepted.count).to eq(1)
      expect(accepted.first.semantic_profile).to eq(payload[:semantic_profile])
    end

    it 'holds cross-profile changes even with later upstream timestamps' do
      ingest
      alternate = payload[:semantic_profile] == 'official-team-totals-v1' ? 'sports-reference-legacy-v1' : 'official-team-totals-v1'
      correction = payload.deep_merge(semantic_profile: alternate, source_updated_at: '2025-01-03T11:00:00Z',
                                      home: { score: 102, stats: { points: 102, two_pt_made: 25, field_goals_made: 36 } })
      expect(ingest(correction)).to include(outcome: 'conflict', reason: 'provider_or_profile_conflict')
      expect(Game.last.home_team_score).to eq(100)
    end

    it 'normalizes one overtime to 45 game minutes and 225 side minutes' do
      overtime = payload.deep_merge(duration_minutes: 45, home: { stats: { minutes: 225 } }, away: { stats: { minutes: 225 } })
      expect(ingest(overtime)).to include(outcome: 'final')
      expect(Game.last).to have_attributes(minutes: 45, possessions: 79.5)
      expect(Game.last.pace).to be_within(0.001).of(70.667)
    end

    it 'rolls back a malformed correction inside an outer transaction' do
      original = ingest
      game = Game.find(original[:game_id])
      before = [game.attributes, game.home_team_game.attributes, game.away_team_game.attributes]
      malformed = payload.deep_merge(source_updated_at: '2025-01-03T11:00:00Z', home: { stats: { points: 101 } })
      Game.transaction { expect(ingest(malformed)).to include(outcome: 'invalid') }
      expect([game.reload.attributes, game.home_team_game.reload.attributes, game.away_team_game.reload.attributes]).to eq(before)
    end

    it 'preserves a manual venue during a valid ordered correction' do
      original = ingest
      game = Game.find(original[:game_id])
      game.update!(venue_type: 'neutral', venue_confidence: 'manual', venue_source: 'manual_override', neutral: true)
      correction = payload.deep_merge(source_updated_at: '2025-01-03T11:00:00Z', home: { score: 102,
                                                                                         stats: { points: 102, two_pt_made: 25,
                                                                                                  field_goals_made: 36 } },
                                      venue: { venue_type: 'home', neutral: false })
      expect(ingest(correction)).to include(outcome: 'final')
      expect(game.reload).to have_attributes(venue_type: 'neutral', venue_confidence: 'manual', neutral: true)
    end

    it 'updates eligible residuals while preserving frozen forecasts and snapshot associations' do
      scheduled = payload.deep_merge(source_status: 'scheduled', source_completed: false, completion_evidence: nil,
                                     home: { score: nil, stats: {} }, away: { score: nil, stats: {} })
      initial = ingest(scheduled)
      game = Game.find(initial[:game_id])
      version = create(:ratings_config_version, name: 'v1.2-default')
      snapshots = [home_team_season, away_team_season].map do |membership|
        create(:team_rating_snapshot, :with_forecast_inputs, team_season: membership, ratings_config_version: version,
                                                             snapshot_date: date - 1)
      end
      context = ProphetRatings::ForecastContext.capture(game, snapshots, version)
      prediction = create(:prediction, game:, ratings_config_version: version, home_team_snapshot: snapshots.first,
                                       away_team_snapshot: snapshots.last, forecast_kind: 'pregame', calculation_context: context,
                                       revision_key: 'synthetic-frozen', generated_at: game.start_time - 1.hour,
                                       forecast_start_time: game.start_time,
                                       input_cutoff: date - 1, home_offensive_efficiency: 110, away_offensive_efficiency: 100,
                                       home_defensive_efficiency: 100, away_defensive_efficiency: 110, pace: 70,
                                       home_win_probability: 0.7, home_score: 76, away_score: 64)
      expect(ingest(payload.merge(source_updated_at: '2025-01-02T12:00:00Z'))).to include(outcome: 'final', game_id: game.id)
      original = prediction.reload.attributes.except('updated_at', *Prediction.column_names.grep(/_error$/))
      correction = payload.deep_merge(source_updated_at: '2025-01-03T11:00:00Z', home: { score: 102,
                                                                                         stats: { points: 102, two_pt_made: 25,
                                                                                                  field_goals_made: 36 } })
      expect(ingest(correction)).to include(outcome: 'final', game_id: game.id)
      expect(prediction.reload.attributes.except('updated_at', *Prediction.column_names.grep(/_error$/))).to eq(original)
      expect(prediction.home_offensive_efficiency_error.to_f).to be_within(0.001).of(110 - (102 / 81.4 * 100).round(3))
      expect(prediction.calculation_context).to eq(context.as_json)
    end

    it 'rolls back all canonical writes when accepted provenance cannot persist' do
      allow(GameObservation).to receive(:create!).and_raise(ActiveRecord::ReadOnlyRecord)
      expect { ingest }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(Game.count).to eq(0)
      expect(TeamGame.count).to eq(0)
      expect(GameExternalIdentity.count).to eq(0)
    end

    it 'holds an older explicitly ordered scheduled revision without changing the accepted schedule' do
      scheduled = payload.deep_merge(source_status: 'scheduled', source_completed: false,
                                     home: { score: nil }, away: { score: nil })
      original = ingest(scheduled)
      older = scheduled.merge(schedule_date: '2025-01-02', source_updated_at: '2025-01-01T11:00:00Z')
      expect(ingest(older)).to include(outcome: 'stale')
      expect(Game.find(original[:game_id]).schedule_date).to eq(date)
    end

    it 'can associate an identical second provider without adopting its provenance' do
      first = ingest
      alternative = payload.merge(provider: 'other-synthetic', external_game_id: 'other-id', source_url: '/other-source')
      expect(ingest(alternative)).to include(outcome: 'unchanged', accepted: false, game_id: first[:game_id])
      expect(GameObservation.where(game_id: first[:game_id], accepted: true).count).to eq(1)
      expect(GameExternalIdentity.where(game_id: first[:game_id]).count).to eq(2)
      expect(Game.find(first[:game_id]).url).to eq(payload[:source_url])
    end
  end

  context 'with a synthetic provider' do
    it_behaves_like 'canonical persistence'
  end

  context 'with the Sports Reference bridge' do
    let(:payload) do
      row = { date:, home_team: home_team.school, away_team: away_team.school, home_team_score: 100, away_team_score: 90,
              home_team_stats:, away_team_stats:, source_completed: true, source_completion_evidence: 'boxscore',
              source_updated_at: canonical_payload[:source_updated_at], url: canonical_payload[:source_url] }
      Ingestion::SportsReferenceObservationAdapter.new(row, season:).call.data
    end

    it_behaves_like 'canonical persistence'
  end
end
