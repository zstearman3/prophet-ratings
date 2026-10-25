# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/fixture')

RSpec.describe OffseasonPerformance::Fixture do
  it 'rejects the ordinary test database before attempting any fixture writes' do
    expect { described_class.guard! }.to raise_error('Refusing non-owned benchmark database')
  end

  it 'rejects another owner checkpoint before restoring persisted records' do
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with('/benchmark/setup-state.json').and_return('{"owner":"foreign"}')
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('BENCHMARK_OWNER').and_return('offseason-abcdef')
    expect { described_class.new(scale: 1).send(:restore) }.to raise_error('Foreign fixture checkpoint')
  end

  it 'checks a fresh persisted preview after the job updates a separate publication instance' do
    season = create(:season)
    create(:team_season, season:)
    model = RatingsConfigVersion.publish!
    admin = create(:user, :admin)
    fixture = described_class.new(scale: 1)
    fixture.state.season = season
    fixture.state.model = model
    fixture.state.admin = admin
    publication = fixture.send(:initial_preview)
    expect(publication.status).to eq('review')
    expect(publication.report.fetch('teams').size).to eq(1)
  end
end
