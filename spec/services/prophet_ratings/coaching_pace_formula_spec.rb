# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::CoachingPaceFormula do
  let(:settings) { { formula: 'relative_pace_v1', weight: 0.2, max_adjustment: 0.5 } }
  let(:inputs) { { reason: 'eligible', target_anchor: 69, source_adjusted_pace: 74, source_baseline: 70 } }
  let(:formula) { described_class.new(inputs, settings) }

  it 'expresses source tempo on the captured anchor and caps the weighted change before rounding' do
    expect(formula.report(68)).to include(old_pace: 68, signal: 73, adjustment: 0.5, new_pace: 68.5)
    settings[:max_adjustment] = 2
    expect(described_class.new(inputs, settings).call(68)).to eq(69)
  end

  it 'applies an equally bounded slower signal' do
    inputs[:source_adjusted_pace] = 64
    expect(formula.report(68)).to include(signal: 63, adjustment: -0.5, new_pace: 67.5)
  end

  it 'makes zero weight and zero cap exact identities' do
    settings[:weight] = 0
    expect(described_class.new(inputs, settings).call(68.123456)).to eq(68.123456)
    settings[:weight] = 1
    settings[:max_adjustment] = 0
    expect(described_class.new(inputs, settings).call(68.123456)).to eq(68.123456)
  end

  it 'leaves excluded inputs unchanged without reading missing source numbers' do
    inputs.replace(reason: 'missing_source_season', target_anchor: 69)
    expect(formula.report(68)).to include(reason: 'missing_source_season', signal: nil, adjustment: 0, new_pace: 68)
  end

  [nil, 0, -1, Float::INFINITY, Float::NAN, '74'].each do |value|
    it "rejects an invalid captured pace operand #{value.inspect}" do
      inputs[:source_adjusted_pace] = value
      expect { formula.call(68) }.to raise_error(ArgumentError, /finite positive/)
    end
  end

  it 'rejects invalid signals and nonpositive outputs' do
    inputs[:source_adjusted_pace] = 1
    inputs[:source_baseline] = 100
    expect { formula.call(68) }.to raise_error(ArgumentError, /finite positive/)
    inputs.merge!(source_adjusted_pace: 1, source_baseline: 69)
    settings.merge!(weight: 1, max_adjustment: 100)
    expect(described_class.new(inputs, settings).call(68)).to eq(1)
  end

  [[:weight, -0.1], [:weight, 1.1], [:weight, Float::NAN], [:max_adjustment, -1],
   [:max_adjustment, Float::INFINITY], [:formula, 'unknown']].each do |key, value|
    it "rejects invalid model settings #{key}=#{value}" do
      settings[key] = value
      expect { formula.call(68) }.to raise_error(ArgumentError)
    end
  end
end
