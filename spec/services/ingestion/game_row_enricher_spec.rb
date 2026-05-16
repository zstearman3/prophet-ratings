# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::GameRowEnricher do
  let!(:season) { create(:season, year: 2026, start_date: Date.new(2025, 11, 1), end_date: Date.new(2026, 4, 10)) }
  let!(:michigan) { create(:team, school: 'Michigan', slug: 'michigan', url: '/cbb/schools/michigan/men/') }
  let!(:wake_forest) { create(:team, school: 'Wake Forest', slug: 'wake-forest', url: '/cbb/schools/wake-forest/men/') }
  let!(:oakland) { create(:team, school: 'Oakland', slug: 'oakland', url: '/cbb/schools/oakland/men/') }
  let(:michigan_schedule_rows) do
    [
      schedule_row('Wake Forest', 'N', 'Little Caesars Arena', Time.zone.local(2025, 11, 11, 18, 30),
                   '/cbb/boxscores/2025-11-11-00-michigan.html'),
      schedule_row('Oakland', '', 'Crisler Arena', Time.zone.local(2025, 11, 11, 20, 30),
                   '/cbb/boxscores/2025-11-11-01-michigan.html'),
      schedule_row('Texas Christian', '@', 'Ed & Rae Schollmaier Arena', Time.zone.local(2025, 11, 14, 21, 0),
                   '/cbb/boxscores/2025-11-14-21-texas-christian.html')
    ]
  end
  let(:same_date_rows) do
    [
      game_row('Michigan', 'Wake Forest', Time.zone.local(2025, 11, 11, 18, 30),
               '/cbb/boxscores/2025-11-11-00-michigan.html'),
      game_row('Michigan', 'Oakland', Time.zone.local(2025, 11, 11, 20, 30),
               '/cbb/boxscores/2025-11-11-01-michigan.html')
    ]
  end

  before do
    [michigan, wake_forest, oakland].each do |team|
      create(:team_season, team:, season:)
      create(:team_alias, team:, value: team.school, source: 'sports_reference')
    end

    allow(Scraper::TeamScheduleEnrichmentScraper).to receive(:new) do |team:, **_kwargs|
      rows = case team.school
             when 'Michigan'
               michigan_schedule_rows
             else
               []
             end
      instance_double(Scraper::TeamScheduleEnrichmentScraper, schedule_data: rows)
    end
  end

  def schedule_row(opponent_name, game_location, venue_name, start_time, box_score_url)
    {
      date: start_time.to_date,
      opponent_name:,
      game_location:,
      venue_name:,
      start_time:,
      box_score_url:
    }
  end

  def game_row(home_team, away_team, date, url)
    {
      home_team:,
      away_team:,
      date:,
      url:
    }
  end

  it 'decorates rows by box score URL before falling back to date and opponent matching' do
    enriched_rows = described_class.new(same_date_rows).call

    expect(enriched_rows).to contain_exactly(
      venue_match('Wake Forest', 'neutral', 'Little Caesars Arena', Time.zone.local(2025, 11, 11, 18, 30), true),
      venue_match('Oakland', 'home', 'Crisler Arena', Time.zone.local(2025, 11, 11, 20, 30), false)
    )
  end

  def venue_match(away_team, venue_type, venue_name, date, neutral)
    hash_including(
      home_team: 'Michigan',
      away_team:,
      venue_type:,
      venue_source: 'sports_reference_team_schedule',
      venue_confidence: 'confirmed',
      venue_name:,
      date:,
      neutral:
    )
  end

  it 'does not enrich a same-date game unless the opponent also matches' do
    rows = [
      {
        home_team: 'Michigan',
        away_team: 'Wake Forest',
        date: Time.zone.local(2025, 11, 11, 18, 30),
        url: '/cbb/boxscores/missing-url.html'
      }
    ]

    enriched_row = described_class.new(rows).call.first

    expect(enriched_row).to include(
      venue_type: 'neutral',
      venue_name: 'Little Caesars Arena',
      date: Time.zone.local(2025, 11, 11, 18, 30)
    )
  end

  it "does not enrich rows marked '@' because away venue type is unsupported" do
    original_date = Time.zone.local(2025, 11, 14, 21, 0)
    row = game_row(
      'Texas Christian',
      'Michigan',
      original_date,
      '/cbb/boxscores/2025-11-14-21-texas-christian.html'
    )

    enriched_row = described_class.new([row]).call.first

    expect(enriched_row).to eq(row)
    expect(enriched_row[:venue_type]).not_to eq('neutral')
    expect(enriched_row[:date]).to eq(original_date)
    expect(enriched_row[:venue_name]).to be_nil
  end
end
