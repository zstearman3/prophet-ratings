# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BasketballCalculations::StatFormulae do
  let(:box_class) do
    Struct.new(:two_pt_made, :two_pt_attempted, :three_pt_made, :three_pt_attempted,
               :free_throws_made, :free_throws_attempted, :field_goals_made, :field_goals_attempted,
               :points, :offensive_rebounds, :defensive_rebounds, :rebounds, :assists, :turnovers,
               :steals, :blocks, :opponent_game, :points_allowed, keyword_init: true) do
      include BasketballCalculations::StatFormulae
    end
  end
  let(:box) do
    box_class.new(two_pt_made: 0, two_pt_attempted: 0, three_pt_made: 0, three_pt_attempted: 0,
                  free_throws_made: 0, free_throws_attempted: 0, field_goals_made: 0, field_goals_attempted: 0,
                  points: 0, offensive_rebounds: 0, defensive_rebounds: 0, rebounds: 0, assists: 0,
                  turnovers: 0, steals: 0, blocks: 0, points_allowed: 0)
  end

  %i[two_pt_percentage three_pt_percentage free_throws_percentage field_goals_percentage
     true_shooting_percentage effective_fg_percentage three_pt_attempt_rate free_throw_rate
     three_pt_proficiency assist_rate turnover_rate offensive_rating defensive_rating].each do |stat|
    it "leaves #{stat} undefined without opportunities" do
      expect(box.public_send("calculated_#{stat}")).to be_nil
    end
  end

  %i[offensive_rebound_rate defensive_rebound_rate rebound_rate steal_rate block_rate].each do |stat|
    it "leaves #{stat} undefined without an opponent or opportunities" do
      expect(box.public_send("calculated_#{stat}")).to be_nil
      box.opponent_game = box.dup
      expect(box.public_send("calculated_#{stat}")).to be_nil
    end
  end

  it 'retains observed zero events when opportunities exist' do
    box.two_pt_attempted = box.three_pt_attempted = box.free_throws_attempted = 5
    box.field_goals_attempted = 10
    box.field_goals_made = 1
    box.opponent_game = box.dup
    box.opponent_game.defensive_rebounds = 10
    expect(box.calculated_two_pt_percentage).to eq(0)
    expect(box.calculated_three_pt_percentage).to eq(0)
    expect(box.calculated_free_throws_percentage).to eq(0)
    expect(box.calculated_offensive_rebound_rate).to eq(0)
    expect([box.calculated_turnover_rate, box.calculated_assist_rate]).to eq([0, 0])
  end

  it 'preserves the corrected composite and the finite legacy arithmetic' do
    box.field_goals_attempted = 10
    expect(box.calculated_three_pt_percentage).to be_nil
    expect(box.calculated_three_pt_proficiency).to eq(0)
    expect(box.legacy_three_pt_proficiency).to eq(0)
    box.three_pt_made = 2
    box.three_pt_attempted = 5
    expect(box.calculated_three_pt_proficiency).to eq(0.43333)
    expect(box.legacy_three_pt_proficiency).to eq(0.6)
  end

  [nil, Float::NAN, Float::INFINITY].each do |value|
    it "does not fabricate a field-goal observation from #{value.inspect}" do
      box.field_goals_attempted = 10
      box.field_goals_made = value
      expect(box.calculated_field_goals_percentage).to be_nil
      box.field_goals_attempted = value
      box.field_goals_made = 0
      expect(box.calculated_field_goals_percentage).to be_nil
    end
  end

  it 'preserves missing shot counts and zero total attempts in both composites' do
    expect(box.legacy_three_pt_proficiency).to be_nil
    box.field_goals_attempted = 10
    %i[three_pt_made three_pt_attempted field_goals_attempted].each do |field|
      missing = box.dup
      missing[field] = nil
      expect(missing.calculated_three_pt_proficiency).to be_nil
      expect(missing.legacy_three_pt_proficiency).to be_nil
    end
  end

  it 'does not treat missing possession inputs as zero events' do
    box.field_goals_attempted = 10
    box.turnovers = nil
    expect(box.calculated_possessions).to be_nil
    expect(box.calculated_offensive_rating).to be_nil
  end
end
