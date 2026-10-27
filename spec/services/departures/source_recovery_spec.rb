# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::SourceRecovery do
  it 'rechecks draft state under the publication lock before retaining an upload', :aggregate_failures do
    season = create(:season, year: 2026)
    team = create(:team, school: 'Sample School')
    create(:team_season, season:, team:)
    batch = legacy_departure_batch(season)
    capture_departures(batch)
    save_departure_rows(batch, departure_rows(team))
    operation = Departures::ValidationPreparation.create(batch)
    Departures::ValidationPreparation.new(operation).call
    approval = Departures::ValidationApproval.new(operation.reload).call(reviewer: 'admin@example.com')
    recovery = described_class.new(batch)
    published = nil
    acquisitions = nil
    allow(recovery).to receive(:validate_original).and_wrap_original do |method|
      original_id = method.call
      Departures::ValidationPublication.new(approval).call
      published = batch.reload.attributes
      acquisitions = batch.acquisitions.order(:id).pluck(:id)
      original_id
    end
    upload = StringIO.new(Rails.root.join('spec/fixtures/departures/school.html').binread)
    fields = { 'source_id' => 'source-2', 'url' => departure_fields.dig('sources', '1', 'url'), 'http_status' => '200', 'html' => upload,
               'captured_at' => '2026-10-21T10:00:00Z', 'observed_at' => '2026-10-21T10:00:00Z', 'source_as_of_reason' => 'Unavailable' }
    expect { recovery.call(fields) }.to raise_error(ArgumentError, /Published departure batches are closed/)
    expect(batch.reload.attributes).to eq(published)
    expect(batch.acquisitions.order(:id).pluck(:id)).to eq(acquisitions)
    expect([DepartureApproval.count, OffseasonInputRevision.count, DepartureValidation.count]).to eq([1, 1, 1])
  end
end
