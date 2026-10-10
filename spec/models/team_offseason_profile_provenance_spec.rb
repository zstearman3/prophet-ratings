# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261010030000_validate_offseason_profile_provenance')

RSpec.describe TeamOffseasonProfile do
  let(:team_season) { create(:team_season) }

  it 'distinguishes absent inputs from explicit zero and requires evidence and manual reasons' do
    absent = build(:team_offseason_profile, team_season:, source_reference: nil, observed_on: nil, input_units: {})
    expect(absent).to be_valid
    zero = build(:team_offseason_profile, team_season:, manual_adjustment: 0, manual_adjustment_reason: nil,
                                          source_reference: nil, observed_on: nil, input_units: {})
    expect(zero).not_to be_valid
    expect(zero.errors.attribute_names).to include(:source_reference, :observed_on, :input_units, :manual_adjustment_reason)
    zero.assign_attributes(source_reference: 'Operator reference', observed_on: Date.new(2026, 9, 1),
                           input_units: TeamOffseasonProfile::INPUT_UNITS, manual_adjustment_reason: 'Reviewed no effect')
    expect(zero).to be_valid
  end

  it 'requires one profile per team-season in both model and database' do
    create(:team_offseason_profile, team_season:)
    duplicate = build(:team_offseason_profile, team_season:)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:team_season_id]).to be_present
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'reports synthetic conflicting IDs and aborts migration without changing evidence' do
    connection = ActiveRecord::Base.connection
    connection.remove_index(:team_offseason_profiles, :team_season_id)
    create(:team_offseason_profile, team_season:, manual_adjustment: 1)
    duplicate = build(:team_offseason_profile, team_season:, manual_adjustment: -1)
    duplicate.save!(validate: false)
    before = described_class.order(:id).map(&:attributes)
    expect(described_class.duplicate_team_season_ids).to eq([team_season.id])
    expect { ValidateOffseasonProfileProvenance.new.migrate(:up) }
      .to raise_error(ActiveRecord::MigrationError, /TeamSeason IDs.*#{team_season.id}.*no rows were changed/)
    expect(described_class.order(:id).map(&:attributes)).to eq(before)
    # Transactional specs restore the original unique index along with the synthetic rows.
  end
end
