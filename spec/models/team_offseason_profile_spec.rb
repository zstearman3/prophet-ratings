# frozen_string_literal: true

# == Schema Information
#
# Table name: team_offseason_profiles
#
#  id                    :bigint           not null, primary key
#  coaching_change       :boolean
#  lost_starters         :integer
#  manual_adjustment     :float
#  recruiting_class_rank :integer
#  recruiting_score      :float
#  returning_bpm_total   :float
#  returning_minutes_pct :float
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  team_season_id        :bigint           not null
#
# Indexes
#
#  index_team_offseason_profiles_on_team_season_id  (team_season_id)
#
require 'rails_helper'

RSpec.describe TeamOffseasonProfile do
  subject(:profile) { described_class.new }

  it 'treats missing and unused profile fields as no evidence' do
    profile.assign_attributes(coaching_change: true, lost_starters: 5, recruiting_class_rank: 1, returning_bpm_total: 20)

    expect(profile.efficiency_adjustment).to eq(0)
    expect(profile.adjustment_for(:adj_pace)).to eq(0)
  end

  it 'uses fractional returning minutes and exposes the doubled net effect' do
    profile.assign_attributes(recruiting_score: 40, returning_minutes_pct: 0.8, manual_adjustment: 1)

    expect(profile.adjustment_for(:adj_off_efficiency)).to eq(4)
    expect(profile.adjustment_for(:adj_def_efficiency)).to eq(-4)
    expect(profile.adjustment_for(:adj_off_efficiency) - profile.adjustment_for(:adj_def_efficiency)).to eq(8)
  end

  it 'does not invent recruitment or attrition when only one input exists' do
    profile.recruiting_score = 40
    expect(profile.efficiency_adjustment).to eq(4)

    profile.assign_attributes(recruiting_score: nil, returning_minutes_pct: 0.8)
    expect(profile.efficiency_adjustment).to be_within(0.0001).of(-1)
  end

  it 'bounds extreme finite adjustments in both directions' do
    profile.recruiting_score = 1_000_000
    expect(profile.efficiency_adjustment).to eq(5)

    profile.assign_attributes(recruiting_score: nil, manual_adjustment: -1_000_000)
    expect(profile.efficiency_adjustment).to eq(-5)
  end

  it 'rejects percentages expressed as whole numbers and invalid fractions' do
    [-0.1, 80, Float::NAN, Float::INFINITY].each do |value|
      profile.returning_minutes_pct = value
      profile.valid?
      expect(profile.errors[:returning_minutes_pct]).to be_present
      expect(profile.efficiency_adjustment).to eq(0)
    end
  end

  it 'rejects invalid numeric evidence and safely ignores legacy invalid values' do
    profile.assign_attributes(recruiting_score: Float::INFINITY, manual_adjustment: Float::NAN)
    profile.valid?

    expect(profile.errors[:recruiting_score]).to be_present
    expect(profile.errors[:manual_adjustment]).to be_present
    expect(profile.efficiency_adjustment).to eq(0)
  end

  it 'rejects and ignores negative recruitment scores' do
    profile.assign_attributes(recruiting_score: -20, manual_adjustment: nil)
    profile.valid?
    expect(profile.errors[:recruiting_score]).to be_present
    expect(profile.efficiency_adjustment).to eq(0)
  end
end
