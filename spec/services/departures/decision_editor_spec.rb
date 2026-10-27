# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::DecisionEditor do
  let(:season) { create(:season, year: 2026) }
  let(:team) { create(:team, school: 'Sample School') }
  let(:batch) { legacy_departure_batch(season) }
  let(:operation) { Departures::ValidationPreparation.create(batch) }

  before do
    create(:team_season, season:, team:)
    capture_departures(batch)
    save_departure_rows(batch, departure_rows(team))
    Departures::ValidationPreparation.new(operation).call
  end

  it 'edits one player using captured identities, retains other decisions and queues fresh validation without approval',
     :aggregate_failures do
    editor = described_class.new(batch, operation.id.to_s)
    key = batch.decisions.first.fetch('selection_key')
    page = editor.page(key, {})
    expect(page.fetch(:selection).fetch('player_name_source')).to eq('Alex Alpha')
    expect(page.fetch(:production_options).join).to include('Alpha, Alex')
    allow(PrepareDepartureValidationJob).to receive(:perform_later)
    decision = batch.decisions.first
    stint = decision.fetch('stints').first
    fields = { 'status' => decision.fetch('status'), 'reason' => 'Reviewed captured stint',
               'evidence_source_ids' => decision.fetch('evidence_source_ids'),
               'stints' => { '0' => { 'production_key' => Departures::PlayerIdentity.choice(stint, stint),
                                      'team_id' => team.id.to_s,
                                      'identity_evidence_source_ids' => stint.fetch('identity_evidence_source_ids') } } }
    previous = batch.decisions.drop(1)
    editor.save('rows' => { key => fields })
    expect(batch.reload.decisions.drop(1)).to eq(previous)
    expect(batch.decisions.first.fetch('reason')).to eq('Reviewed captured stint')
    expect(PrepareDepartureValidationJob).to have_received(:perform_later).with(kind_of(Integer))
    expect([DepartureApproval.count, OffseasonInputRevision.count]).to eq([0, 0])
    expect { editor.save('rows' => { key => fields }) }.to raise_error(ArgumentError, /changed/)
  end

  it 'rejects invented captured player and evidence identities without saving' do
    key = batch.decisions.first.fetch('selection_key')
    expect do
      described_class.new(batch, operation.id.to_s).save('rows' => { key => { 'status' => 'unknown_participation', 'reason' => 'Unknown',
                                                                              'evidence_source_ids' => ['invented'], 'stints' => {} } })
    end.to raise_error(ArgumentError, /evidence/)
    expect(DepartureApproval.count).to eq(0)
  end
end
