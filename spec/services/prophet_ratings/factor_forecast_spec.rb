# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::FactorForecast do
  let(:config) { RatingsConfigVersion.authored_config }
  let(:snapshots) do
    [0.4, 0.3].map do |offense|
      build(:team_rating_snapshot, stats: { 'adj_offensive_rebound_rate' => offense,
                                            'adj_defensive_rebound_rate' => 0.75,
                                            'factor_anchors' => { 'offensive_rebound_rate' => 0.3 } })
    end
  end

  it 'uses the complement of defensive rebounding and persists all forecast inputs' do
    forecast = described_class.capture(snapshots, config).fetch('offensive_rebound_rate')
    expect(forecast.fetch('home')).to be_within(1e-10).of(0.35)
    expect(forecast.fetch('away')).to be_within(1e-10).of(0.25)
    expect(forecast.fetch('baseline')).to eq(0.3)
    expect(forecast.fetch('inputs').first).to eq(offense: 0.4, defense: 0.25, baseline: 0.3)
  end

  it 'dampens offense and defense independently around their own frozen anchors' do
    config[:factors][:offensive_rebound_rate].merge!(offense_weight: 0.5, defense_weight: 0)
    expect(described_class.capture(snapshots, config).dig('offensive_rebound_rate', 'home')).to be_within(1e-10).of(0.35)
    config[:factors][:offensive_rebound_rate].merge!(offense_weight: 0, defense_weight: 0)
    expect(described_class.capture(snapshots, config).dig('offensive_rebound_rate', 'home')).to eq(0.3)
  end

  it 'omits factors with missing anchors or ratings instead of fabricating historical forecasts' do
    snapshots.first.stats.delete('factor_anchors')
    expect(described_class.capture(snapshots, config)).to be_empty
    expect(described_class.capture(snapshots, config.except(:factors))).to be_empty
  end

  it 'rejects incomplete, unknown, nonfinite and out-of-range configuration' do
    [nil, -1, Float::NAN, 1.1].each do |value|
      config[:factors][:offensive_rebound_rate][:defense_weight] = value
      expect { described_class.validate(config) }.to raise_error(ArgumentError, /Factor/)
    end
    config[:factors].delete(:turnover_rate)
    expect { described_class.validate(config) }.to raise_error(ArgumentError, /five factors/)
  end

  it 'reports paired factor and league-average errors without zero-filling missing results' do
    observation = ProphetRatings::FactorEvaluation.observation({ 'home' => 0.4, 'baseline' => 0.3 }, 'home', 0.35)
    metrics = ProphetRatings::FactorEvaluation.summary([observation])
    expect(metrics[:model][:mae]).to be_within(1e-10).of(0.05)
    expect(metrics[:model][:bias]).to be_within(1e-10).of(0.05)
    expect(metrics[:baseline][:bias]).to be_within(1e-10).of(-0.05)
    expect(ProphetRatings::FactorEvaluation.observation({ 'home' => 0.4 }, 'home', 0.35)).to be_nil
    expect(ProphetRatings::FactorEvaluation.summary([])[:model]).to include(observations: 0, mae: nil)
  end
end
