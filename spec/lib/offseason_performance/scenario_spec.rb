# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/driver')

RSpec.describe OffseasonPerformance::Scenario do
  let(:fixture) do
    { 'season_id' => 1, 'publication_id' => 2, 'cbbd_id' => 3, 'departure_id' => 4,
      'schedule_season_id' => 5, 'schedule_date' => '2024-11-01' }
  end

  it 'keeps schedule imports on the prior season and posts the exact bounded day' do
    scenario = described_class.new('schedule', 'serial', fixture)
    expect(scenario.path(nil)).to eq('/admin/schedule_refresh_runs?season_id=5')
    expect(scenario.form(nil)).to include('refresh[start_date]' => '2024-11-01', 'refresh[end_date]' => '2024-11-01',
                                          'refresh[provider]' => 'cbbd', 'refresh[max_requests]' => '20', 'refresh[retries]' => '0')
    expect(scenario.http_method).to eq(Net::HTTP::Post)
  end

  it 'requires the reviewed fingerprint and acknowledgement for a real publication post' do
    publication = instance_double(PreseasonPublication, id: 7, fingerprint: 'exact-fingerprint')
    scenario = described_class.new('publish', 'serial', fixture)
    expect(scenario.path(publication)).to eq('/admin/preseason_publications/7/publish?season_id=1')
    expect(scenario.form(publication)).to eq('fingerprint' => 'exact-fingerprint', 'acknowledge' => '1')
    expect(scenario.expected_status).to eq('published')
  end
end
