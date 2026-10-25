# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/solver_job')

RSpec.describe OffseasonPerformance::SolverJob do
  let(:expected) { Array.new(730) { |index| index.even? ? 2.0 : -3.0 } }

  it 'verifies every coefficient of the independently known repeated-identity solution' do
    expect(described_class.verify(expected.dup, expected)).to eq(0)
    expect { described_class.verify(expected.first(729), expected) }.to raise_error(/coefficient count/)
  end

  it 'rejects a nonnumeric or nonfinite tail even when the preceding coefficients are correct' do
    [Float::NAN, Float::INFINITY, '2.0'].each do |invalid|
      actual = expected.dup
      actual[-1] = invalid
      expect { described_class.verify(actual, expected) }.to raise_error(/Invalid real solver coefficient/)
    end
  end
end
