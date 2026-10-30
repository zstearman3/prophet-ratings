# frozen_string_literal: true

RSpec.shared_context 'with name-only schedule conflict' do
  include_context 'with schedule conflict evidence'

  let(:teams) { [create(:team, school: 'Synthetic Home')] }
  let(:incoming_opponent) { 'New Visitor' }
  let(:existing_payload) do
    { contract_version: 'ingestion-v1', semantic_profile: 'official-team-totals-v1', provider: 'cbbd',
      external_game_id: 'old-1', season_year: season.year, schedule_date: date.iso8601, start_time: nil,
      source_status: 'scheduled', source_completed: false, captured_at: '2026-10-26T12:00:00Z', source_updated_at: nil,
      adapter_revision: Ingestion::Cbbd::ImportObservation::REVISION, completion_evidence: nil, duration_minutes: nil,
      home: { name: teams.first.school, external_team_id: 'home-1', score: nil, stats: {} },
      away: { name: 'Old Visitor', external_team_id: 'visitor-old', score: nil, stats: {} },
      venue: { venue_name: 'Synthetic Arena' } }
  end
  let(:incoming_payload) do
    existing_payload.merge(away: { name: incoming_opponent, external_team_id: 'visitor-new', score: nil, stats: {} })
  end

  def retain_name_only_conflict(payload)
    game
    result = Ingestion::GameObservationImporter.new(observation: payload, season:).call
    rejected = GameObservation.find(result.fetch(:observation_id))
    retained = GameObservation.create!(rejected.attributes.except('id', 'created_at', 'updated_at').merge(
                                         game_id: nil, reason: "date_rolled_back: #{rejected.reason}"
                                       ))
    run.checkpoint('date' => date.iso8601, 'error' => 'conflict', 'rejection_observation_ids' => [retained.id])
    retained
  end

  def described_resolution(source, choice, fingerprint)
    Ingestion::ScheduleReviewResolution.new(run:, observation: source, user: admin, choice:, fingerprint:).call
  end
end
