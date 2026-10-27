# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::ScheduleReviewResolution do
  include_context 'with schedule conflict evidence'

  it 'reproduces the adjacent-date conflict and compares both retained entries' do
    expect(observation.reason).to eq('date_rolled_back: provider_or_profile_conflict')
    evidence = schedule_evidence
    expect(evidence.game).to eq(game)
    expect(evidence.prior.external_game_id).to eq('old-1')
    expect(evidence.incoming.data[:external_game_id]).to eq('new-2')
  end

  %w[existing incoming].each do |choice|
    it "keeps the #{choice} entry and makes unchanged discarded facts a safe retry" do
      evidence = schedule_evidence
      fingerprint = evidence.fingerprint
      original = evidence.prior.attributes
      sides = TeamGame.where(game:).order(:id).map(&:attributes)
      review = resolve_schedule(choice, fingerprint:)
      selected, ignored = choice == 'existing' ? %w[old-1 new-2] : %w[new-2 old-1]
      ignored_payload = choice == 'existing' ? incoming_payload : existing_payload
      aggregate_failures do
        expect(review).to have_attributes(reason: 'Approved by admin', reviewed_by: admin, game:,
                                          selected_external_id: selected, ignored_external_id: ignored)
        expect(GameExternalIdentity.active.where(game:).pluck(:external_id)).to eq([selected])
        expect(GameExternalIdentity.find_by!(provider: 'cbbd', external_id: ignored)).to be_superseded
        expect(game.reload.schedule_date).to eq(choice == 'existing' ? date - 1 : date)
        expect(Game.count).to eq(1)
        expect(TeamGame.where(game:).order(:id).map(&:attributes)).to eq(sides)
        expect(evidence.prior.reload.attributes).to eq(original)
        expect(observation.reload.accepted).to be(false)
      end
      result = Ingestion::GameObservationImporter.new(observation: ignored_payload, season:).call
      expect(result).to include(outcome: 'reviewed_skip', game_id: game.id, accepted: false, applied: false)
      expect(Ingestion::GameSyncResult.new(games: [result], imported_rows: 0).call[:complete]).to be(true)
      expect(resolve_schedule(choice, fingerprint:)).to eq(review)
      expect(GameScheduleReview.count).to eq(1)
    end

    it "completes the failed date on retry after keeping the #{choice} schedule" do
      resolve_schedule(choice)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('CBBD_API_KEY', nil).and_return('synthetic')
      allow(ENV).to receive(:fetch).with('CBBD_CAPTURE_DIRECTORY', nil).and_return('/tmp/synthetic-schedule')
      rows = [schedule_source_row(incoming_payload)]
      acquired = { 'complete' => true, 'observations' => rows, 'acquisition' => { 'complete' => true, 'attempts' => 1 } }
      allow(Ingestion::Cbbd::Adapter).to receive(:new).and_return(instance_double(Ingestion::Cbbd::Adapter, call: acquired))
      child = run.create_retry!(admin)
      Ingestion::ScheduleRefreshExecution.new(child).call
      aggregate_failures do
        expect(child.reload.status).to eq('succeeded')
        expect(child.pending_dates).to be_empty
        expect(Game.count).to eq(1)
        expect(GameScheduleReview.count).to eq(1)
        expect(run.reload.pending_dates).to eq([date.iso8601])
        expect(child.report.fetch('days').sole['imported_rows']).to eq(choice == 'existing' ? 0 : 1)
      end
    end
  end

  it 'does not apply a stale comparison or a changed source' do
    fingerprint = schedule_evidence.fingerprint
    game.update!(venue_name: 'Admin correction')
    expect { resolve_schedule(fingerprint:) }.to raise_error(ArgumentError, /changed/i)
    expect(GameScheduleReview.count).to eq(0)
    fingerprint = schedule_evidence.fingerprint
    GameObservation.create!(observation.attributes.except('id', 'created_at', 'updated_at').merge(
                              normalized_payload: observation.normalized_payload.merge('start_time' => '2026-12-09T20:00:00Z')
                            ))
    expect { resolve_schedule(fingerprint:) }.to raise_error(ArgumentError, /changed/i)
    expect(GameScheduleReview.count).to eq(0)
  end

  it 'requires a valid explicit choice and admin, without a justification' do
    schedule_evidence
    expect { resolve_schedule('') }.to raise_error(ArgumentError, /select|choose/i)
    expect { resolve_schedule('other') }.to raise_error(ArgumentError, /select|choose/i)
    expect { resolve_schedule(user: create(:user)) }.to raise_error(ArgumentError, /admin/i)
    expect(GameScheduleReview.count).to eq(0)
  end

  it 'holds changed discarded facts and preserves generic superseded protections' do
    resolve_schedule
    changed = incoming_payload.merge(start_time: '2026-12-09T20:00:00Z')
    result = Ingestion::GameObservationImporter.new(observation: changed, season:).call
    expect(result).to include(outcome: 'superseded', applied: false)
    expect(Ingestion::GameSyncProvider.held?(result)).to be(true)
  end

  it 'rejects completed, scored, canceled, or participant-changed candidates' do
    fingerprint = schedule_evidence.fingerprint
    %w[final canceled final_unmatched].each do |status|
      game.update!(status:)
      expect { resolve_schedule(fingerprint:) }.to raise_error(ArgumentError)
    end
    game.update!(status: 'scheduled', home_team_score: 10)
    expect { resolve_schedule(fingerprint:) }.to raise_error(ArgumentError)
    game.update!(home_team_score: nil)
    game.home_team_game.update!(points: 10)
    expect { resolve_schedule(fingerprint:) }.to raise_error(ArgumentError)
    game.home_team_game.update!(points: nil, team: create(:team))
    expect { resolve_schedule(fingerprint:) }.to raise_error(ArgumentError)
    expect(GameScheduleReview.count).to eq(0)
  end

  it 'rejects changed stored memberships without repairing sides through schedule approval' do
    schedule_evidence
    other_season = create(:season, year: 2026)
    other_membership = create(:team_season, team: teams.first, season: other_season)
    game.home_team_game.update!(team_season: other_membership)
    %w[existing incoming].each do |choice|
      expect { resolve_schedule(choice) }.to raise_error(ArgumentError, /membership/i)
    end
    expect(GameScheduleReview.count).to eq(0)
    expect(game.home_team_game.reload.team_season_id).to eq(other_membership.id)
  end

  it 'holds a discarded entry if its selected identity has since been replaced' do
    resolve_schedule
    GameExternalIdentity.active.find_by!(game:, provider: 'cbbd').supersede!(external_id: 'third-3')
    result = Ingestion::GameObservationImporter.new(observation: incoming_payload, season:).call
    expect(result).to include(outcome: 'superseded', applied: false)
    expect(Ingestion::GameSyncProvider.held?(result)).to be(true)
  end

  it 'rejects expired comparisons and leaves a busy import untouched' do
    fingerprint = schedule_evidence.fingerprint
    travel_to Time.utc(2026, 12, 10, 12) do
      expect { resolve_schedule(fingerprint:) }.to raise_error(ArgumentError, /upcoming/i)
    end
    allow(Ingestion::GamesIngestionService).to receive(:with_date_lock).and_raise(Ingestion::GamesIngestionService::ImportInProgress)
    expect { resolve_schedule(fingerprint:) }.to raise_error(Ingestion::GamesIngestionService::ImportInProgress)
    expect(GameScheduleReview.count).to eq(0)
    expect(GameExternalIdentity.active.where(game:).pluck(:external_id)).to eq(['old-1'])
  end

  it 'rolls back metadata and identity changes when the review cannot be stored' do
    fingerprint = schedule_evidence.fingerprint
    state = [game.reload.attributes, GameExternalIdentity.order(:id).map(&:attributes), GameObservation.count]
    allow(GameScheduleReview).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
    expect { resolve_schedule('incoming', fingerprint:) }.to raise_error(ActiveRecord::RecordInvalid)
    expect([game.reload.attributes, GameExternalIdentity.order(:id).map(&:attributes), GameObservation.count]).to eq(state)
  end
end
