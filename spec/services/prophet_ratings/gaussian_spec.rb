# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::Gaussian do
  it 'returns both cached samples in order and consumes exactly two uniforms per pair' do
    uniforms = [0.0, 1 - Math.exp(-0.5), 0.0, 0.0]
    generator = described_class.new(10.0, 2.0, -> { uniforms.shift })

    expect(generator.rand).to be_within(1e-12).of(12.0)
    expect(uniforms.size).to eq(2)
    expect([generator.rand, uniforms.size]).to eq([10.0, 2])
    expect(Array.new(2) { generator.rand }).to eq([10.0, 10.0])
    expect(uniforms).to be_empty
  end
end
