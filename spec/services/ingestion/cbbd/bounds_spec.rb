# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::Cbbd::Bounds do
  it 'includes the final millisecond and respects the Eastern daylight saving boundary' do
    bounds = described_class.new(season: 2026, start_date: '2025-11-02', end_date: '2025-11-02')
    expect(bounds.to_h).to include('start_time' => '2025-11-02T04:00:00.000Z', 'end_time' => '2025-11-03T04:59:59.999Z')
    expect(bounds.end_time - bounds.start_time).to be_within(0.0001).of(89_999.999)
  end
end
