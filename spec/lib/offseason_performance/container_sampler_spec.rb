# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require Rails.root.join('script/performance/runner')

RSpec.describe OffseasonPerformance::ContainerSampler do
  it 'preserves missing counters and discloses sampled-only peaks instead of inventing zeros' do
    sample = described_class.parse('', 'owned-id', 'worker')
    expect(sample).to include('current_bytes' => nil, 'peak_bytes' => nil, 'rss_bytes' => nil, 'peak_method' => 'sampled_only')
    expect(OffseasonPerformance::Budgets.container([sample], { 'Running' => false })).to include('missing current counters')
  end
end
