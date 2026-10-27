# frozen_string_literal: true

RSpec.shared_context 'with schedule conflict evidence' do
  include ActiveSupport::Testing::TimeHelpers

  let(:season) { create(:season, year: 2027, start_date: '2026-11-01', end_date: '2027-04-10') }
  let(:admin) { create(:user, admin: true) }
  let(:teams) { [create(:team, school: 'Synthetic Home'), create(:team, school: 'Synthetic Away')] }
  let(:date) { Date.new(2026, 12, 9) }
  let(:existing_payload) do
    { contract_version: 'ingestion-v1', semantic_profile: 'official-team-totals-v1', provider: 'cbbd',
      external_game_id: 'old-1', season_year: season.year, schedule_date: (date - 1).iso8601,
      start_time: '2026-12-09T00:00:00Z', source_status: 'scheduled', source_completed: false,
      captured_at: '2026-10-26T12:00:00Z', source_updated_at: nil, adapter_revision: Ingestion::Cbbd::ImportObservation::REVISION,
      completion_evidence: nil, duration_minutes: nil,
      home: { name: teams.first.school, external_team_id: 'home-1', score: nil, stats: {} },
      away: { name: teams.last.school, external_team_id: 'away-1', score: nil, stats: {} },
      venue: { venue_name: 'Synthetic Arena' } }
  end
  let(:incoming_payload) { existing_payload.merge(external_game_id: 'new-2', schedule_date: date.iso8601, start_time: nil) }
  let(:initial) { Ingestion::GameObservationImporter.new(observation: existing_payload, season:).call }
  let(:game) { Game.find(initial.fetch(:game_id)) }
  let(:run) do
    ScheduleRefreshRun.create!(season:, requested_by: admin, provider: 'cbbd', mode: 'upcoming',
                               start_date: date, end_date: date, max_requests: 5, retries: 0, status: 'incomplete')
  end
  let(:observation) do
    game
    report = Ingestion::GameObservationImporter.new(observation: incoming_payload, season:).call
    rejected = GameObservation.find(report.fetch(:observation_id))
    retained = GameObservation.create!(rejected.attributes.except('id', 'created_at', 'updated_at').merge(
                                         game_id: nil, reason: "date_rolled_back: #{rejected.reason}"
                                       ))
    run.update!(report: { days: [{ date: date.iso8601, error: 'conflict', rolled_back: true,
                                   rejection_observation_ids: [retained.id], outcomes: { conflict: 1 } }] })
    retained
  end

  before do
    travel_to Time.utc(2026, 10, 26, 12)
    teams.each_with_index do |team, index|
      create(:team_season, team:, season:)
      TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: index.zero? ? 'home-1' : 'away-1')
    end
  end

  def schedule_evidence
    Ingestion::ScheduleReviewEvidence.new(observation, season).validate
  end

  def schedule_source_row(payload)
    { 'format' => 'ingestion-v1', 'provider' => 'cbbd', 'semantic_profile' => 'official-team-totals-v1',
      'normalization_version' => Ingestion::CanonicalObservation::NORMALIZATION_VERSION,
      'source_game_id' => payload[:external_game_id], 'season' => season.year,
      'schedule_date' => payload[:schedule_date], 'start_time' => payload[:start_time],
      'status' => 'scheduled', 'source_completed' => false, 'provenance' => [{ 'captured_at' => payload[:captured_at] }],
      'venue' => { 'name' => 'Synthetic Arena' } }.merge(%i[home away].to_h do |label|
        side = payload.fetch(label)
        [label.to_s, { 'source_name' => side[:name], 'source_team_id' => side[:external_team_id],
                       'score' => { 'value' => nil }, 'stats' => {} }]
      end)
  end

  def resolve_schedule(choice = 'existing', fingerprint: schedule_evidence.fingerprint, user: admin)
    Ingestion::ScheduleReviewResolution.new(run:, observation:, user:, choice:, fingerprint:).call
  end
end
