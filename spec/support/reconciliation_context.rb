# frozen_string_literal: true

RSpec.shared_context 'with synthetic reconciliation' do
  let(:season) { create(:season, year: 2026) }
  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/ingestion/cbbd/final.json').read) }
  let(:observation) do
    entry = ->(raw) { { 'raw' => raw, 'provenance' => { 'id' => 'synthetic' } } }
    Ingestion::Cbbd::Normalizer.new(entry.call(fixture['games'].first), fixture['boxes'].map(&entry)).call
  end
  let(:replay) do
    { 'bounds' => { 'season' => 2026, 'start_date' => '2025-11-01', 'end_date' => '2025-11-02' },
      'observations' => [observation], 'complete' => true, 'acquisition' => { 'complete' => true, 'decisions' => [] } }
  end
  let(:teams) { %w[Home Away].map { |side| create(:team, school: "Synthetic #{side}") } }
  let(:game) do
    create(:game, season:, start_time: '2025-11-01T23:00:00Z', home_team_name: teams.first.school,
                  away_team_name: teams.last.school, home_team_score: 65, away_team_score: 64)
  end

  before do
    teams.each { |team| create(:team_season, team:, season:) }
  end

  def report
    Ingestion::Reconciliation::Comparison.new(season:, replay:).call
  end

  def choices
    [*teams.each_with_index.map do |team, index|
      { 'entity' => 'team', 'external_id' => ((index + 1) * 10).to_s,
        'local_id' => team.id, 'action' => 'associate' }
    end,
     { 'entity' => 'game', 'external_id' => '1', 'local_id' => game.id, 'action' => 'associate' }]
  end

  def decisions(comparison = report)
    { 'fingerprint' => comparison.fetch('fingerprint'), 'reviewer' => 'synthetic operator',
      'reason' => 'Checked synthetic evidence', 'choices' => choices }
  end

  def apply(comparison, submission = decisions(comparison))
    Ingestion::Reconciliation::Apply.new(comparison:, replay:, decisions: submission).call
  end
end
