# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::ValidationPreparation do
  let(:season) { create(:season, year: 2026) }
  let(:prior) { create(:season, year: 2025) }
  let(:team) { create(:team, school: 'Sample School') }
  let(:transfer) { create(:team, school: 'Transfer College') }
  let(:outside) { create(:team, school: 'New College') }
  let(:batch) { Departures::CapturePreparation.create(season, {}) }
  let(:nullable_id) { false }
  let(:unknown_points) { false }

  before do
    [team, transfer, outside].each { |college| create(:team_season, season:, team: college) }
    [team, transfer].each { |college| create(:team_season, season: prior, team: college) }
    { team => 20, transfer => 10, outside => 30 }.each do |college, id|
      TeamExternalIdentity.associate!(team: college, provider: 'cbbd', external_id: id.to_s)
    end
    stub_cbbd
    AcquireDepartureBatchJob.perform_now(batch.attempt.id)
  end

  def cbbd_picks
    super.tap { |rows| rows.first['athleteId'] = nil if nullable_id }
  end

  def cbbd_players(scope)
    super.tap do |rows|
      rows << rows.first.merge('teamId' => 10, 'team' => 'Transfer College', 'points' => scope == 'regular' ? 40 : 10)
      rows.first['points'] = nil if unknown_points
    end
  end

  def cbbd_teams(scope)
    super + [{ 'season' => 2025, 'teamId' => 10, 'team' => 'Transfer College', 'games' => scope == 'regular' ? 30 : 2, 'totalMinutes' => 80,
               'teamStats' => { 'points' => { 'total' => scope == 'regular' ? 160 : 40 } } }]
  end

  def prepare
    operation = described_class.create(batch)
    described_class.new(operation).call
    failures = DepartureDatasetNormalization.order(:id).last.rows.where(kind: 'failures').pluck(:fact)
    expect(operation.reload.status).to eq('ready'), "#{operation.error}; #{failures}"
    operation
  end

  it 'prepares the exact automatic proposal without approving or changing original capture evidence', :aggregate_failures do
    original = batch.attempt
    snapshot = original.attributes.deep_dup
    expected = Departures::DraftTeamSnapshot.new(batch, original).dataset
    operation = prepare
    expect(operation.departure_dataset_normalization.dataset_revision).to eq(expected.fetch('dataset_revision'))
    preview = Departures::Preview.new(dataset: expected, review: operation.choices.fetch('review')).call
    expect(operation.report.except('gaps')).to eq(preview)
    expect(operation.report.fetch('accounted_selections')).to eq(60)
    expect([DepartureApproval.count, OffseasonInputRevision.count, TeamOffseasonProfile.count]).to eq([0, 0, 0])
    expect(original.reload.attributes).to eq(snapshot)
    approval = Departures::ValidationApproval.new(operation).call(reviewer: 'admin@example.com')
    revision = Departures::ValidationPublication.new(approval).call
    expect(batch.reload.attempt.predecessor_id).to eq(original.id)
    expect(original.reload.attributes).to eq(snapshot)
    expect(batch.plan.fetch('extraction_version')).to eq(Departures::CbbdDataset::AUTOMATIC_EXTRACTION)
    expect(batch.decisions).to eq(approval.document.fetch('decisions'))
    expect(revision.reload.team_input(team.id).fetch('loss_share')).to eq(0.25)
    expect(revision.team_input(transfer.id).fetch('loss_share')).to eq(0.25)
    expect(revision.team_input(outside.id).fetch('loss_share')).to eq(0.0)
  end

  it 'stales a guided certificate when a pending header changes only integer/float representation', :aggregate_failures do
    changes = []
    allow(Departures::PreparedAnnualDataset).to receive(:reference).and_wrap_original do |method, *arguments|
      reference = method.call(*arguments)
      before = described_class.generation
      template = "UPDATE departure_dataset_normalizations SET header = jsonb_set(header, '{target_year}', '2026.0'::jsonb) WHERE id = ?"
      ApplicationRecord.connection.execute(ApplicationRecord.sanitize_sql_array([template, reference.id]))
      changes << [before, described_class.generation]
      reference
    end
    operation = described_class.create(batch)
    described_class.new(operation).call
    expect(changes.length).to eq(1)
    expect(changes.first.last).to be > changes.first.first
    expect(operation.reload.status).to eq('stale'), operation.error
    expect(operation).not_to be_current
    expect([DepartureApproval.count, OffseasonInputRevision.count, TeamOffseasonProfile.count]).to eq([0, 0, 0])
  end

  context 'with a missing draft athlete ID' do
    let(:nullable_id) { true }

    it 'retains the original null and every cross-school stint after the within-college name match' do
      operation = prepare
      row = operation.report.fetch('selections').first
      expect(row).to include('draft_provider_athlete_id' => nil, 'provider_athlete_id' => 1,
                             'matched_provider_athlete_id' => 1, 'match_method' => 'exact_name_within_college')
      expect(row.fetch('source_row')['athleteId']).to be_nil
      expect(row.fetch('stints').pluck('provider_team_id')).to eq([10, 20])
      expected = Departures::DraftTeamSnapshot.new(batch, batch.attempt).dataset
      preview = Departures::Preview.new(dataset: expected, review: operation.choices.fetch('review')).call
      expect(operation.report.except('gaps')).to eq(preview)
      expect(row.fetch('evidence_source_ids')).to eq(batch.attempt.manifest.fetch('sources').pluck('id'))
    end
  end

  context 'with explicit null player points' do
    let(:unknown_points) { true }

    it 'preserves local unknowns, known transfer production and unrelated verified zero without a new gap checkbox' do
      operation = prepare
      approval = Departures::ValidationApproval.new(operation).call(reviewer: 'admin@example.com')
      expect(approval.document.fetch('partial_acknowledgement')).to eq({})
      revision = Departures::ValidationPublication.new(approval).call.reload
      expect(revision.team_input(team.id).fetch('loss_share')).to be_nil
      expect(revision.team_input(transfer.id).fetch('loss_share')).to eq(0.25)
      expect(revision.team_input(outside.id).fetch('loss_share')).to eq(0.0)
    end
  end
end
