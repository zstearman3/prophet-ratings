# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::ScheduleReviewResolution do
  include_context 'with name-only schedule conflict'

  choices = %w[existing incoming]
  ['New Visitor', 'Old Visitor'].each do |opponent|
    context "when the incoming opponent is #{opponent}" do
      let(:incoming_opponent) { opponent }

      choices.each do |choice|
        it "keeps #{choice} participant evidence and skips only the exact discarded facts" do
          expect(observation.reason).to eq('date_rolled_back: participant_or_orientation_conflict')
          evidence = schedule_evidence
          fingerprint = evidence.fingerprint
          original = evidence.prior.attributes
          sides = TeamGame.where(game:).map(&:attributes)
          review = resolve_schedule(choice, fingerprint:)
          selected_id = choice == 'incoming' ? 'visitor-new' : 'visitor-old'
          selected_name = choice == 'incoming' ? opponent : 'Old Visitor'
          discarded = choice == 'incoming' ? existing_payload : incoming_payload

          aggregate_failures do
            expect(review).to have_attributes(reason: 'Approved by admin', reviewed_by: admin, game:)
            expect(review.selected_payload.dig('away', 'external_team_id')).to eq(selected_id)
            expect(game.reload.away_team_name).to eq(selected_name)
            expect(TeamGame.where(game:).map(&:attributes)).to eq(sides)
            expect(GameExternalIdentity.where(game:).pluck(:external_id, :superseded_at)).to eq([['old-1', nil]])
            expect(evidence.prior.reload.attributes).to eq(original)
            expect(observation.reload.accepted).to be(false)
          end
          result = Ingestion::GameObservationImporter.new(observation: discarded, season:).call
          expect(result).to include(outcome: 'reviewed_skip', accepted: false, applied: false, game_id: game.id)
          changed = discarded.merge(away: discarded.fetch(:away).merge(external_team_id: 'visitor-third'))
          held = Ingestion::GameObservationImporter.new(observation: changed, season:).call
          expect(held).to include(outcome: 'conflict', applied: false)
          expect(resolve_schedule(choice, fingerprint:)).to eq(review)
        end

        it "completes the failed date after keeping #{choice}, without changing memberships" do
          resolve_schedule(choice)
          allow(ENV).to receive(:fetch).and_call_original
          allow(ENV).to receive(:fetch).with('CBBD_API_KEY', nil).and_return('synthetic')
          allow(ENV).to receive(:fetch).with('CBBD_CAPTURE_DIRECTORY', nil).and_return('/tmp/synthetic-schedule')
          acquired = { 'complete' => true, 'observations' => [schedule_source_row(incoming_payload)],
                       'acquisition' => { 'complete' => true, 'attempts' => 1 } }
          allow(Ingestion::Cbbd::Adapter).to receive(:new).and_return(instance_double(Ingestion::Cbbd::Adapter, call: acquired))
          child = run.create_retry!(admin)
          Ingestion::ScheduleRefreshExecution.new(child).call
          aggregate_failures do
            expect(child.reload.status).to eq('succeeded')
            expect(child.pending_dates).to be_empty
            expect([Game.count, Team.count, TeamSeason.count, TeamGame.count]).to eq([1, 1, 1, 1])
            expect(GameObservation.where(game:, accepted: true).order(:id).last.normalized_payload.dig('away', 'external_team_id'))
              .to eq(choice == 'incoming' ? 'visitor-new' : 'visitor-old')
          end
        end
      end
    end
  end

  it 'allows a later same-key correction without reusing obsolete participant decisions' do
    resolve_schedule('incoming')
    third_payload = incoming_payload.merge(away: incoming_payload[:away].merge(name: 'Third Visitor', external_team_id: 'visitor-third'))
    source = retain_name_only_conflict(third_payload)
    evidence = Ingestion::ScheduleReviewEvidence.new(source, season).validate
    review = described_resolution(source, 'incoming', evidence.fingerprint)
    aggregate_failures do
      expect(GameScheduleReview.count).to eq(2)
      expect(review.selected_payload.dig('away', 'external_team_id')).to eq('visitor-third')
      expect(game.reload.away_team_name).to eq('Third Visitor')
      expect(Ingestion::GameObservationImporter.new(observation: incoming_payload, season:).call[:outcome]).to eq('reviewed_skip')
      expect(Ingestion::GameObservationImporter.new(observation: existing_payload, season:).call[:outcome]).to eq('conflict')
    end
  end

  it 'rejects scored or completed games' do
    fingerprint = schedule_evidence.fingerprint
    %w[final canceled final_unmatched].each do |status|
      game.update!(status:)
      expect { resolve_schedule('incoming', fingerprint:) }.to raise_error(ArgumentError, /unplayed/i)
    end
    game.update!(status: 'scheduled', away_team_score: 1)
    expect { resolve_schedule('incoming', fingerprint:) }.to raise_error(ArgumentError, /scoreless/i)
    game.update!(away_team_score: nil)
    game.home_team_game.update!(points: 1)
    expect { resolve_schedule('incoming', fingerprint:) }.to raise_error(ArgumentError, /scoreless/i)
    expect(GameScheduleReview.count).to eq(0)
  end

  it 'rejects expired or changed linked participants' do
    fingerprint = schedule_evidence.fingerprint
    travel_to Time.utc(2026, 12, 10, 12) do
      expect { resolve_schedule('incoming', fingerprint:) }.to raise_error(ArgumentError, /upcoming/i)
    end
    game.home_team_game.update!(team: create(:team))
    expect { resolve_schedule('incoming', fingerprint:) }.to raise_error(ArgumentError, /membership/i)
    expect(GameScheduleReview.count).to eq(0)
  end

  it 'protects saved odds and rejects dependencies created after comparison' do
    fingerprint = schedule_evidence.fingerprint
    create(:game_odd, game:, fetched_at: Time.current)
    expect { resolve_schedule('incoming', fingerprint:) }.to raise_error(ArgumentError, /Saved forecasts, odds/)
    expect(game.reload.away_team_name).to eq('Old Visitor')
    expect(GameScheduleReview.count).to eq(0)
  end

  %w[visitor-old visitor-new].each do |external_id|
    it "invalidates the comparison when #{external_id} receives a mapping without a season membership" do
      fingerprint = schedule_evidence.fingerprint
      target = create(:team, school: 'Unrated mapping target')
      TeamExternalIdentity.associate!(team: target, provider: 'cbbd', external_id:)
      expect { resolve_schedule('incoming', fingerprint:) }.to raise_error(ArgumentError, /changed/i)
      expect(game.reload.away_team_name).to eq('Old Visitor')
      expect(GameScheduleReview.count).to eq(0)
    end
  end

  it 'rejects an expired canonical game even when both source payloads describe a future game' do
    observation
    travel_to Time.utc(2026, 12, 8, 12) do
      game.update!(start_time: Game.schedule_time_for(Date.new(2026, 12, 7)))
      expect { schedule_evidence }.to raise_error(ArgumentError, /upcoming/i)
      expect(GameScheduleReview.count).to eq(0)
    end
  end

  it 'protects bookmaker odds even when no aggregated odds exist' do
    observation
    create(:bookmaker_odd, game:, fetched_at: Time.current, bookmaker: 'Synthetic', market: 'h2h')
    expect { schedule_evidence }.to raise_error(ArgumentError, /Saved forecasts, odds/)
    expect(GameScheduleReview.count).to eq(0)
  end

  it 'rejects a canonical game from another season even when its date and memberships match the evidence' do
    observation
    other_season = create(:season, year: 2028, start_date: season.start_date, end_date: season.end_date)
    game.update!(season: other_season)
    state = [game.attributes, GameObservation.order(:id).map(&:attributes), TeamGame.where(game:).map(&:attributes)]

    expect { resolve_schedule('incoming') }.to raise_error(ArgumentError, /target season/i)
    expect([game.reload.attributes, GameObservation.order(:id).map(&:attributes), TeamGame.where(game:).map(&:attributes)]).to eq(state)
    expect(GameScheduleReview.count).to eq(0)
  end

  it 'rejects an incoming opponent that now resolves to a rated membership' do
    observation
    visitor = create(:team, school: 'New Visitor')
    create(:team_season, team: visitor, season:)
    TeamExternalIdentity.associate!(team: visitor, provider: 'cbbd', external_id: 'visitor-new')
    expect { schedule_evidence }.to raise_error(ArgumentError, /name-only/i)
    expect(game.reload.away_team_game).to be_nil
  end

  it 'rejects changed linked-side external identity even when its label resolves to the same team' do
    TeamExternalIdentity.associate!(team: teams.first, provider: 'cbbd', external_id: 'changed-home')
    payload = incoming_payload.merge(home: incoming_payload[:home].merge(external_team_id: 'changed-home'))
    source = retain_name_only_conflict(payload)
    expect(source.reason).to include('participant_or_orientation_conflict')
    expect { Ingestion::ScheduleReviewEvidence.new(source, season).validate }.to raise_error(ArgumentError, /Linked participant identity/)
    expect(GameScheduleReview.count).to eq(0)
  end

  it 'protects existing saved forecasts' do
    observation
    snapshot = create(:team_rating_snapshot, team_season: game.home_team_season)
    create(:prediction, game:, home_team_snapshot: snapshot, away_team_snapshot: snapshot,
                        ratings_config_version: snapshot.ratings_config_version)
    expect { schedule_evidence }.to raise_error(ArgumentError, /Saved forecasts, odds/)
    expect(GameScheduleReview.count).to eq(0)
  end

  it 'rejects a stale source or canonical comparison and preserves manual venue corrections' do
    observation
    game.update!(venue_name: 'Manual Arena', venue_source: 'manual_override', venue_confidence: 'manual')
    fingerprint = schedule_evidence.fingerprint
    game.update!(start_time: Game.schedule_time_for(date) + 2.hours)
    expect { resolve_schedule('incoming', fingerprint:) }.to raise_error(ArgumentError, /changed/i)
    fingerprint = schedule_evidence.fingerprint
    retained = retain_name_only_conflict(incoming_payload.merge(venue: { venue_name: 'Source Arena changed' }))
    expect { Ingestion::ScheduleReviewEvidence.new(observation, season).validate }.to raise_error(ArgumentError, /Source facts changed/)
    evidence = Ingestion::ScheduleReviewEvidence.new(retained, season).validate
    described_resolution(retained, 'incoming', evidence.fingerprint)
    expect(game.reload.venue_name).to eq('Manual Arena')
  end

  it 'rolls back a participant change and accepted provenance when storing the decision fails' do
    fingerprint = schedule_evidence.fingerprint
    state = [game.attributes, GameObservation.count, TeamGame.where(game:).map(&:attributes)]
    allow(GameScheduleReview).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
    expect { resolve_schedule('incoming', fingerprint:) }.to raise_error(ActiveRecord::RecordInvalid)
    expect([game.reload.attributes, GameObservation.count, TeamGame.where(game:).map(&:attributes)]).to eq(state)
  end
end
