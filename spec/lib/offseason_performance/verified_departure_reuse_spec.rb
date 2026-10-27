# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/fixture')
require Rails.root.join('script/performance/verified_departure_reuse')

RSpec.describe OffseasonPerformance::VerifiedDepartureReuse do
  let(:season) { create(:season, year: 2026) }
  let(:team) { create(:team, school: 'Sample School') }
  let(:batch) { legacy_departure_batch(season) }

  before do
    create(:team_season, season:, team:)
    capture_departures(batch)
    save_departure_rows(batch, departure_rows(team))
    allow(OffseasonPerformance::Fixture).to receive(:guard!)
  end

  it 'creates all independent cases before authenticating and reuses only exact same-generation complete content' do
    operations = described_class.clone_cases(batch.id, 3)
    source = operations.first
    Departures::ValidationPreparation.new(source).call
    generation = source.reload.generation
    described_class.new(source).call(operations.second)
    expect(operations.second.reload).to have_attributes(status: 'ready', generation:)
    expect(operations.second.proposals.pluck(:input)).to eq(source.proposals.pluck(:input))
    expect(operations.second.choices.fetch('review').fetch('revision_id')).not_to eq(source.choices.fetch('review').fetch('revision_id'))
    altered = operations.third.departure_acquisition.reload
    overwrite_departure_record(altered, evidence: altered.evidence.merge('extra' => { 'snapshot_base64' => 'AA==' }))
    expect { described_class.new(source.reload).call(operations.third) }.to raise_error(/current|generation|equal/)
    expect([DepartureApproval.count, OffseasonInputRevision.count]).to eq([0, 0])
  end

  it 'compares complete ordered JSON, including numeric representation and extra metadata, before sealing' do
    operations = described_class.clone_cases(batch.id, 2)
    candidate = operations.last
    altered = candidate.departure_acquisition.reload
    data = altered.dataset.deep_dup
    data.fetch('production').first.fetch('players').first['player_points'] = 500.0
    overwrite_departure_record(altered, dataset: data)
    source = operations.first
    Departures::ValidationPreparation.new(source).call
    expect(source.reload.status).to eq('ready')
    expect { described_class.new(source).call(candidate) }.to raise_error(/equal/)
    expect(candidate.reload.generation).to be_nil
  end
end
