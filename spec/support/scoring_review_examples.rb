# frozen_string_literal: true

RSpec.shared_context 'with scoring review evidence' do
  let(:date) { Date.new(2025, 11, 1) }
  let(:season) { create(:season, year: 2026, start_date: date, end_date: date + 30.days) }
  let(:admin) { create(:user, :admin) }
  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/ingestion/cbbd/final.json').read) }
  let(:source_game) { fixture.fetch('games').first }
  let(:boxes) { fixture.fetch('boxes') }
  let(:run) do
    ScheduleRefreshRun.create!(season:, requested_by: admin, provider: 'cbbd', mode: 'historical',
                               start_date: date, end_date: date, max_requests: 2, retries: 0, status: 'incomplete')
  end
  let(:row) do
    Ingestion::Cbbd::Normalizer.new(source_entry(source_game, 0),
                                    boxes.each_with_index.map { |box, index| source_entry(box, index + 1) }).call
  end
  let(:observation) do
    report = Ingestion::HistoricalSyncObservation.new(row, season).call
    record = GameObservation.find(report.fetch(:observation_id))
    run.update!(report: { days: [{ date: date.iso8601, error: 'Held', rejection_observation_ids: [record.id] }] })
    record
  end

  before do
    allow(Game).to receive(:current_schedule_date).and_return(date + 31.days)
    %w[home away].each do |label|
      team = create(:team, school: source_game.fetch("#{label}Team"))
      create(:team_season, team:, season:)
      TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: source_game.fetch("#{label}TeamId").to_s)
    end
    # A reported 65-64 win whose supplied home shooting counts total 63.
    boxes.first['teamStats']['freeThrows']['made'] = 8
    boxes.last['opponentStats']['freeThrows']['made'] = 8
  end

  def source_entry(raw, index)
    { 'raw' => raw, 'provenance' => { 'id' => "synthetic-#{index}", 'sha256' => 'synthetic', 'row_index' => index,
                                      'captured_at' => '2025-11-02T12:00:00Z' } }
  end

  def approve(choices = { 'home' => '65' }, confirmed: '1')
    Ingestion::ScoringReviewImport.new(run:, observation:, user: admin, choices:, confirmed:).call
  end
end
