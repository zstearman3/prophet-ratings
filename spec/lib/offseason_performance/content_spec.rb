# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/content')

RSpec.describe OffseasonPerformance::Content do
  it 'keeps the target roster fixed and doubles evidence and history' do
    one = described_class.new(scale: 1).cardinalities
    two = described_class.new(scale: 2).cardinalities
    expect(two['target_teams']).to eq(365)
    expect(two['historical_snapshots']).to eq(120_450)
    expect(two['cbbd_game_observations']).to eq(20_000)
    expect(two['player_observations']).to eq(2 * one['player_observations'])
  end

  it 'generates deterministic nested roster evidence and all sixty draft picks' do
    content = described_class.new(scale: 1)
    expect(described_class.totals(1, 1)).to include('Final archived observation 2')
    expect(content.draft.scan('<p>').size).to eq(60)
    expect(described_class.totals(1, 1).scan('roster/athlete-').size).to eq(15)
    expect { described_class.new(scale: 3) }.to raise_error(ArgumentError)
  end
end
