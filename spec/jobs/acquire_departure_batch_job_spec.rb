# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AcquireDepartureBatchJob do
  it 'queues validation after a completed capture, without approval or duplicate work on redelivery' do
    season = create(:season, year: 2026)
    create(:team_season, season:)
    batch = Departures::CapturePreparation.create(season, {})
    stub_cbbd
    allow(PrepareDepartureValidationJob).to receive(:perform_later)

    described_class.perform_now(batch.attempt.id)
    operation = DepartureValidation.last
    expect(operation).to have_attributes(status: 'queued', departure_batch_id: batch.id,
                                         departure_acquisition_id: batch.attempt.id)
    expect(PrepareDepartureValidationJob).to have_received(:perform_later).with(operation.id).once
    expect([DepartureApproval.count, OffseasonInputRevision.count, TeamOffseasonProfile.count]).to eq([0, 0, 0])

    expect { described_class.perform_now(batch.attempt.id) }.not_to change(DepartureValidation, :count)
    expect(Ingestion::Cbbd::HttpTransport).to have_received(:call).exactly(5).times
  end
end
