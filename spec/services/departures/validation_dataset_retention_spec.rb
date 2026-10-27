# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::ValidationDatasetRetention do
  let(:season) { create(:season, year: 2026) }
  let(:team) { create(:team, school: 'Sample School') }

  before do
    allow(AcquireDepartureBatchJob).to receive(:perform_later)
    allow(PrepareDepartureValidationJob).to receive(:perform_later)
    create(:team_season, season:, team:)
    create(:team_season, season: create(:season, year: 2025), team:)
    TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: '20')
    stub_cbbd
  end

  def validate(batch)
    operation = Departures::ValidationPreparation.queue(batch)
    Departures::ValidationPreparation.new(operation).call
    expect(operation.reload.status).to eq('ready'), operation.error
    operation
  end

  it 'retains the canonical offline dataset separately from the authenticated publication proposal', :aggregate_failures do
    batch = Departures::CapturePreparation.create(season, {})
    AcquireDepartureBatchJob.perform_now(batch.attempt.id)
    first = validate(batch)
    fields = { 'review_key' => first.id.to_s, 'expected_picks' => (1..60).to_a.join(' '),
               'confirm_picks' => '1', 'picks_evidence' => 'Independent final draft reference',
               'confirm_scope' => '1', 'scope_evidence' => 'Reviewed completed college season' }
    Departures::PreparedCoverageReview.new(batch).save(fields, reviewer: 'admin@example.com')
    successor = batch.reload.attempt
    expect(successor.dataset['storage_version']).to eq(Departures::BatchSuccessor::PENDING)
    operation = validate(batch)
    successor.reload
    canonical = Departures::RetainedEvidence.new(successor).verified_dataset(successor.plan)
    expect(canonical['dataset_revision']).to eq(successor.dataset['dataset_revision'])
    expect(successor.dataset['normalization_id']).not_to eq(operation.departure_dataset_normalization_id)
    expect(Departures::BatchReview.new(batch).report.fetch('errors')).to be_empty
    expect(Ingestion::Cbbd::HttpTransport).to have_received(:call).exactly(5).times
  end
end
