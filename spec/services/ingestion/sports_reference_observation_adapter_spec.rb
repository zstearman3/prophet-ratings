# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::SportsReferenceObservationAdapter do
  let(:row) do
    { date: Game::SCHEDULE_TIME_ZONE.parse('2025-01-01 19:00'), home_team: 'Home', away_team: 'Away',
      url: '/cbb/boxscores/2025-01-01-home.html' }
  end

  it 'treats legacy Ruby times without precision metadata as date-only observations' do
    data = described_class.new(row).call.validate.data
    expect(data).to include(start_time: nil, schedule_date: '2025-01-01', source_updated_at: nil,
                            semantic_profile: 'sports-reference-legacy-v1')
  end

  it 'retains a known parsed tip only with explicit parser precision' do
    data = described_class.new(row.merge(time_precision: 'instant')).call.validate.data
    expect(Time.iso8601(data[:start_time])).to eq(row[:date])
  end

  it 'does not turn a shared date URL into a stable game ID' do
    data = described_class.new(row.merge(url: '/cbb/boxscores/index.cgi?day=1')).call.data
    expect(data[:external_game_id]).to be_nil
  end
end
