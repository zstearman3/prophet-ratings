# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::PreseasonComparisonCandidate do
  let(:config) { RatingsConfigVersion.authored_config }
  let(:calendar) { described_class.new('baseline_calendar', config) }
  let(:games) { described_class.new('baseline_effective_games', config) }

  it 'retains the day gate, calendar floor and two-result qualification' do
    expect(calendar.weight(days: 14, games: 4, effective_games: 4)).to eq(1.0)
    expect(calendar.weight(days: 15, games: 4, effective_games: 4)).to eq(0.625)
    expect(calendar.weight(days: 50, games: 4, effective_games: 4)).to eq(0.1)
    expect(calendar.weight(days: 50, games: 1, effective_games: 1)).to eq(1.0)
  end

  it 'decays only with evidence rather than elapsed days or postponements' do
    expect(games.weight(days: 1, games: 2, effective_games: 2)).to eq(0.8)
    expect(games.weight(days: 20, games: 8, effective_games: 8)).to eq(0.5)
    expect(games.weight(days: 29, games: 0, effective_games: 0)).to eq(1.0)
    expect(games.weight(days: 29, games: 2, effective_games: 1.5)).to eq(0.8421)
  end

  it 'uses a fixed baseline for absent second-year history without changing the common cohort' do
    prior = build(:team_rating_snapshot, adj_offensive_efficiency: 120, adj_defensive_efficiency: 100, adj_pace: 70)
    baselines = { 'adj_offensive_efficiency' => 110, 'adj_defensive_efficiency' => 105, 'adj_pace' => 69 }
    candidate = described_class.new('multiyear_calendar', config)
    expect(candidate.prior(prior, nil, baselines)).to eq('adj_offensive_efficiency' => 117.0,
                                                         'adj_defensive_efficiency' => 101.5, 'adj_pace' => 69.7)
    older = build(:team_rating_snapshot, adj_offensive_efficiency: 100, adj_defensive_efficiency: 110, adj_pace: 68)
    expect(candidate.prior(prior, older, baselines)).to eq('adj_offensive_efficiency' => 115.5,
                                                           'adj_defensive_efficiency' => 102.25, 'adj_pace' => 69.55)
  end
end
