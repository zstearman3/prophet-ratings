# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::Cbbd::StatField do
  [true, false, 1.5, -1, 'NaN', 'Infinity', '1.0', '1x', '2147483648', Float::INFINITY, Float::NAN].each do |raw|
    it "rejects #{raw.inspect} rather than clipping or converting to zero" do
      expect(described_class.new({ 'count' => raw }, ['count']).call).to include('value' => nil, 'reason' => 'invalid_nonnegative_integer')
    end
  end

  [0, 1, 1.0, ' 001 '].each do |raw|
    it "preserves lossless #{raw.inspect}" do
      result = described_class.new({ 'count' => raw }, ['count']).call
      expect(result).to include('value' => raw.to_i, 'raw' => raw, 'availability' => 'observed')
    end
  end
end
