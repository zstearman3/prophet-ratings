# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::ValidationPublication do
  let(:season) { create(:season, year: 2026) }
  let(:team) { create(:team, school: 'Sample School') }
  let(:batch) { legacy_departure_batch(season) }

  before do
    create(:team_season, season:, team:)
    capture_departures(batch)
    save_departure_rows(batch, departure_rows(team))
  end

  def approval_for(batch)
    operation = Departures::ValidationPreparation.create(batch)
    Departures::ValidationPreparation.new(operation).call
    expect(operation.reload.status).to eq('ready'), operation.error
    Departures::ValidationApproval.new(operation).call(reviewer: 'admin@example.com')
  end

  it 'authenticates publication receipts before returning a caller-forged result pointer' do
    approval = approval_for(batch)
    revision = described_class.new(approval).call
    operation = approval.departure_validation.reload
    overwrite_departure_record(operation, offseason_input_revision_id: nil)
    expect { described_class.new(approval.reload).call }.to raise_error(ArgumentError, /publication|receipt/i)
    expect(TeamOffseasonProfile.distinct.pluck(:departure_revision_id)).to eq([revision.id])
  end

  it 'keeps exact retries pinned to their original revision after a later correction' do
    original = approval_for(batch)
    first = described_class.new(original).call
    correction = Departures::BatchPreparation.new(batch.reload).correct('Reviewed correction')
    save_departure_rows(correction, departure_rows(team))
    later = described_class.new(approval_for(correction)).call
    expect(later.id).not_to eq(first.id)
    expect(described_class.new(original.reload).call.id).to eq(first.id)
    expect(TeamOffseasonProfile.distinct.pluck(:departure_revision_id)).to eq([later.id])
  end

  it 'rejects SQL replacement of annual facts with timestamps preserved' do
    approval = approval_for(batch)
    operation = approval.departure_validation
    row = DepartureDatasetRow.where(departure_dataset_normalization_id: operation.departure_dataset_normalization_id,
                                    kind: 'production').first!
    corrupt_departure_fact(row, row.fact.merge('team_points' => 1))
    expect { described_class.new(approval).call }.to raise_error(ArgumentError, /artifacts changed/)
    expect([OffseasonInputRevision.count, TeamOffseasonProfile.count]).to eq([0, 0])
  end

  it 'rejects replaced proposals and reports even when supplied hashes are recomputed' do
    approval = approval_for(batch)
    operation = approval.departure_validation
    proposal = operation.proposals.first!
    overwrite_departure_record(proposal, input: proposal.input.merge('loss_share' => 0.0))
    expect(operation.reload).not_to be_current
    expect { described_class.new(approval).call }.to raise_error(ArgumentError, /changed/)
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'rolls revision, pointers, batch and audit result back together on interruption' do
    approval = approval_for(batch)
    allow(Departures::ProfilePublication).to receive(:new).and_wrap_original do |constructor, *args|
      constructor.call(*args).tap do |writer|
        allow(writer).to receive(:link).and_wrap_original do |method, id|
          method.call(id)
          raise Interrupt, 'synthetic interruption'
        end
      end
    end
    expect { described_class.new(approval).call }.to raise_error(Interrupt)
    expect([OffseasonInputRevision.count, TeamOffseasonProfile.count]).to eq([0, 0])
    expect(batch.reload).to have_attributes(status: 'draft', revision_id: nil)
    expect(approval.departure_validation.reload.offseason_input_revision_id).to be_nil
  end

  it 'preserves scalar validation failures rather than replacing invalid preexisting inputs' do
    profile = TeamOffseasonProfile.create!(team_season: season.team_seasons.first!)
    overwrite_departure_record(profile, returning_minutes_pct: 1.5)
    approval = approval_for(batch)
    expect { described_class.new(approval).call }.to raise_error(ArgumentError, %r{evidence/units})
    expect(OffseasonInputRevision.count).to eq(0)
    expect(profile.reload.returning_minutes_pct).to eq(1.5)
  end

  it 'validates existing recruiting revision coverage without loading its annual payload through models' do
    review = { 'review_status' => 'reviewed', 'approval' => { 'approved_by' => 'admin', 'approved_at' => Time.current.iso8601 } }
    payload = { 'kind' => 'recruiting', 'dataset_hash' => 'a' * 64, 'review_hash' => Departures::Contract.digest(review),
                'review' => review, 'team_inputs' => {} }
    recruiting = OffseasonInputRevision.create!(season:, kind: 'recruiting', version: 'existing-recruiting', reason: 'Approved by admin',
                                                payload:, input_hash: Departures::Contract.digest(payload),
                                                dataset_hash: payload.fetch('dataset_hash'), review_hash: payload.fetch('review_hash'))
    profile = TeamOffseasonProfile.create!(team_season: season.team_seasons.first!)
    overwrite_departure_record(profile, recruiting_revision_id: recruiting.id)
    approval = approval_for(batch)
    expect { described_class.new(approval).call }.to raise_error(ArgumentError, /recruiting revision must cover/)
    expect(OffseasonInputRevision.where(kind: 'departures')).to be_empty
    expect(profile.reload.recruiting_revision_id).to eq(recruiting.id)
  end
end
