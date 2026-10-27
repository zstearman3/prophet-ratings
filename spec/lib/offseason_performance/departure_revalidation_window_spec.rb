# frozen_string_literal: true

require 'rails_helper'
require 'net/http'
require Rails.root.join('script/performance/fixture')
require Rails.root.join('script/performance/verified_departure_reuse')
require Rails.root.join('script/performance/job_driver')
require Rails.root.join('script/performance/measurements')
require Rails.root.join('script/performance/departure_validation_http')
require Rails.root.join('script/performance/departure_revalidation_window')

RSpec.describe OffseasonPerformance::DepartureRevalidationWindow do
  let(:season) { create(:season, year: 2026) }
  let(:batch) { legacy_departure_batch(season) }

  it 'requires forty new operations and jobs while preserving held approvals and rejecting duplicate shortcuts', :aggregate_failures do
    capture_departures(batch)
    save_departure_rows(batch, departure_rows(create(:team, school: 'Sample School')))
    allow(OffseasonPerformance::Fixture).to receive(:guard!)
    originals = OffseasonPerformance::VerifiedDepartureReuse.clone_cases(batch.id, 40)
    originals.each { |operation| operation.update!(status: 'failed') }
    cases = JSON.generate('batch_ids' => originals.map(&:departure_batch_id))
    allow(File).to receive(:read).with('/benchmark/departure-validation-cases.json').and_return(cases)
    allow(OffseasonPerformance::JobDriver).to receive(:queue).and_return('owned_revalidation_heavy')
    prior = GoodJob::Job.create!(job_class: 'PublishDepartureValidationJob', queue_name: 'owned_confirmation_heavy', serialized_params: {})
    allow(PrepareDepartureValidationJob).to receive(:perform_later) do |id|
      GoodJob::Job.create!(job_class: 'PrepareDepartureValidationJob', queue_name: 'owned_revalidation_heavy',
                           serialized_params: { 'arguments' => [id] })
    end
    allow(OffseasonPerformance::DepartureValidationHttp).to receive(:request) do |_client, path, method:|
      expect(method).to eq(Net::HTTP::Post)
      id = path.split('/').fetch(3)
      Departures::ValidationPreparation.queue(DepartureBatch.find(id))
      { 'valid' => true }
    end
    allow(OffseasonPerformance::Measurements).to receive(:check)
    window = described_class.new(Object.new)
    result = {}
    window.call(result)
    expect(result.fetch('warmups').length).to eq(10)
    expect(result.fetch('samples').length).to eq(30)
    expect(result.fetch('revalidation').fetch('distinct_new_operations')).to eq(40)
    expect(prior.reload).to have_attributes(performed_at: nil, finished_at: nil)
    expect([DepartureApproval.count, OffseasonInputRevision.count, TeamOffseasonProfile.count]).to eq([0, 0, 0])
    expect { window.call({}) }.to raise_error(/forty new scalar-ID/)
  end
end
