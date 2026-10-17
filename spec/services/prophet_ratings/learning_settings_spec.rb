# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::LearningSettings do
  it 'preserves historical thresholds, scale, cap, and precision when the block is absent' do
    rule = described_class.for({}, :volatility)
    expect([0, 3, 4, 5, 8, 20].map { |count| described_class.weight(count, rule) }).to eq([0, 0, 0.25, 0.3125, 0.5, 0.5])
    expect(described_class.weight(1, described_class.for({}, :home_court))).to eq(0.0625)
  end

  it 'allows independent learning thresholds and caps including disabling learning' do
    rule = { minimum_observations: 5, sample_scale: 10.0, maximum_weight: 0.8 }
    expect([4, 5, 6, 20].map { |count| described_class.weight(count, rule) }).to eq([0, 0.5, 0.6, 0.8])
    expect(described_class.weight(20, rule.merge(maximum_weight: 0))).to eq(0)
  end

  it 'applies the selected model to volatility blending and home-court learning' do
    payload = RatingsConfigVersion.authored_config
    payload[:learning][:volatility].merge!(minimum_observations: 2, sample_scale: 4, maximum_weight: 1)
    payload[:learning][:home_court][:maximum_weight] = 0
    version = RatingsConfigVersion.publish!(payload)
    service = ProphetRatings::TeamSeasonStatsAggregator.new(season: create(:season), ratings_config_version: version)
    # Sample SD of [8, 12] is sqrt(8); n/4 gives half weight.
    expect(service.send(:blend_volatility, [8, 12], 10)).to be_within(1e-10).of(5 + (Math.sqrt(8) / 2))
    expect(service.send(:learning_weight, 20, :home_court)).to eq(0)
    expect(service.send(:blend_volatility, [8], 10)).to eq(10)
  end

  it 'rejects malformed, nonfinite and inconsistent learning rules' do
    payload = RatingsConfigVersion.authored_config
    [{ minimum_observations: 1 }, { minimum_observations: 2.5 }, { sample_scale: 0 },
     { sample_scale: Float::INFINITY }, { maximum_weight: 1.1 }, { maximum_weight: -1 }].each do |override|
      invalid = payload.deep_dup
      invalid[:learning][:volatility].merge!(override)
      expect { described_class.validate(invalid) }.to raise_error(ArgumentError, /learning/)
    end
    expect { described_class.validate(learning: nil) }.to raise_error(ArgumentError, /learning/)
  end
end
