# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Importer::GameVenueEnricher do
  let(:season) { create(:season, year: 2025, start_date: Date.new(2024, 11, 1), end_date: Date.new(2025, 4, 10)) }
  let(:home_team) { create(:team, school: 'Houston', location: 'Houston, TX', home_venue: 'Fertitta Center') }
  let(:away_team) { create(:team, school: 'Alabama', location: 'Tuscaloosa, AL', home_venue: 'Coleman Coliseum') }
  let(:home_team_season) { create(:team_season, season:, team: home_team) }
  let(:away_team_season) { create(:team_season, season:, team: away_team) }
  let(:game) do
    create(
      :game,
      season:,
      start_time: Time.zone.local(2024, 11, 18, 19, 0),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      location:,
      venue_type: 'unknown',
      venue_source: nil,
      venue_confidence: 'unknown'
    )
  end
  let(:location) { nil }

  before do
    create(:team_game, game:, team: home_team, team_season: home_team_season, home: true)
    create(:team_game, game:, team: away_team, team_season: away_team_season, home: false)
    allow(Scraper::TeamScheduleEnrichmentScraper).to receive(:new)
      .and_return(instance_double(Scraper::TeamScheduleEnrichmentScraper, schedule_data: []))
  end

  it 'does not overwrite manually classified games with scraped data' do
    game.update!(
      location: 'Fertitta Center',
      venue_type: 'neutral',
      venue_source: 'manual_override',
      venue_confidence: 'manual',
      venue_name: 'T-Mobile Arena',
      neutral: true
    )

    described_class.new(game).call

    expect(game.reload).to have_attributes(
      venue_type: 'neutral',
      venue_source: 'manual_override',
      venue_confidence: 'manual',
      venue_name: 'T-Mobile Arena',
      neutral: true
    )
  end

  it 'overwrites manually classified games when requested' do
    game.update!(
      location: 'Fertitta Center',
      venue_type: 'neutral',
      venue_source: 'manual_override',
      venue_confidence: 'manual',
      venue_name: 'T-Mobile Arena',
      neutral: true
    )

    described_class.new(game, overwrite_manual: true).call

    expect(game.reload).to have_attributes(
      venue_type: 'home',
      venue_source: 'sports_reference_box_score_header',
      venue_confidence: 'confirmed',
      venue_name: 'Fertitta Center',
      neutral: false
    )
  end

  it 'marks a game neutral from a Sports Reference team schedule row' do
    schedule_scraper = instance_double(
      Scraper::TeamScheduleEnrichmentScraper,
      schedule_data: [
        {
          date: game.start_time.to_date,
          opponent_name: away_team.school,
          game_location: 'N',
          venue_name: 'Little Caesars Arena'
        }
      ]
    )
    allow(Scraper::TeamScheduleEnrichmentScraper).to receive(:new).with(team: home_team, season:).and_return(schedule_scraper)

    described_class.new(game).call

    expect(game.reload).to have_attributes(
      venue_type: 'neutral',
      venue_source: 'sports_reference_team_schedule',
      venue_confidence: 'confirmed',
      venue_name: 'Little Caesars Arena',
      neutral: true
    )
  end

  it 'marks a game home when the Sports Reference team schedule row location is blank' do
    schedule_scraper = instance_double(
      Scraper::TeamScheduleEnrichmentScraper,
      schedule_data: [
        {
          date: game.start_time.to_date,
          opponent_name: away_team.school,
          game_location: '',
          venue_name: 'Fertitta Center'
        }
      ]
    )
    allow(Scraper::TeamScheduleEnrichmentScraper).to receive(:new).with(team: home_team, season:).and_return(schedule_scraper)

    described_class.new(game).call

    expect(game.reload).to have_attributes(
      venue_type: 'home',
      venue_source: 'sports_reference_team_schedule',
      venue_confidence: 'confirmed',
      venue_name: 'Fertitta Center',
      neutral: false
    )
  end

  it "marks a game home when the away team's Sports Reference team schedule row location is '@'" do
    home_schedule_scraper = instance_double(Scraper::TeamScheduleEnrichmentScraper, schedule_data: [])
    away_schedule_scraper = instance_double(
      Scraper::TeamScheduleEnrichmentScraper,
      schedule_data: [
        {
          date: game.start_time.to_date,
          opponent_name: home_team.school,
          game_location: '@',
          venue_name: 'Fertitta Center'
        }
      ]
    )
    allow(Scraper::TeamScheduleEnrichmentScraper).to receive(:new).with(team: home_team, season:).and_return(home_schedule_scraper)
    allow(Scraper::TeamScheduleEnrichmentScraper).to receive(:new).with(team: away_team, season:).and_return(away_schedule_scraper)

    described_class.new(game).call

    expect(game.reload).to have_attributes(
      venue_type: 'home',
      venue_source: 'sports_reference_team_schedule',
      venue_confidence: 'confirmed',
      venue_name: 'Fertitta Center',
      neutral: false
    )
  end

  it "leaves venue unknown when the home team's Sports Reference team schedule row location is '@'" do
    schedule_scraper = instance_double(
      Scraper::TeamScheduleEnrichmentScraper,
      schedule_data: [
        {
          date: game.start_time.to_date,
          opponent_name: away_team.school,
          game_location: '@',
          venue_name: 'Coleman Coliseum'
        }
      ]
    )
    allow(Scraper::TeamScheduleEnrichmentScraper).to receive(:new).with(team: home_team, season:).and_return(schedule_scraper)

    described_class.new(game).call

    expect(game.reload).to have_attributes(
      venue_type: 'unknown',
      venue_source: nil,
      venue_confidence: 'unknown',
      venue_name: nil,
      neutral: nil
    )
  end

  it 'prioritizes the Sports Reference team schedule row over legacy header location text' do
    game.update!(location: 'Fertitta Center')
    schedule_scraper = instance_double(
      Scraper::TeamScheduleEnrichmentScraper,
      schedule_data: [
        {
          date: game.start_time.to_date,
          opponent_name: away_team.school,
          game_location: 'N',
          venue_name: 'Little Caesars Arena'
        }
      ]
    )
    allow(Scraper::TeamScheduleEnrichmentScraper).to receive(:new).with(team: home_team, season:).and_return(schedule_scraper)

    described_class.new(game).call

    expect(game.reload).to have_attributes(
      venue_type: 'neutral',
      venue_source: 'sports_reference_team_schedule',
      venue_confidence: 'confirmed',
      venue_name: 'Little Caesars Arena',
      neutral: true
    )
  end

  it 'is idempotent' do
    game.update!(location: 'Fertitta Center')

    described_class.new(game).call
    first_attributes = game.reload.attributes.slice('venue_type', 'venue_source', 'venue_confidence', 'venue_name', 'neutral')

    described_class.new(game).call

    expect(game.reload.attributes.slice('venue_type', 'venue_source', 'venue_confidence', 'venue_name', 'neutral')).to eq(first_attributes)
  end

  context 'when Sports Reference provides a home venue location' do
    let(:location) { 'Fertitta Center' }

    it 'marks the game as confirmed home' do
      described_class.new(game).call

      expect(game.reload).to have_attributes(
        venue_type: 'home',
        venue_source: 'sports_reference_box_score_header',
        venue_confidence: 'confirmed',
        venue_name: 'Fertitta Center',
        neutral: false
      )
    end
  end

  context 'when only the box-score location is present and does not confirm a home game' do
    let(:location) { 'Neutral Court' }

    it 'leaves the venue unknown' do
      allow(Scraper::TeamScheduleEnrichmentScraper).to receive(:new).and_raise(StandardError)

      described_class.new(game).call

      expect(game.reload).to have_attributes(
        venue_type: 'unknown',
        venue_source: nil,
        venue_confidence: 'unknown',
        venue_name: nil,
        neutral: nil
      )
    end
  end

  context 'when location is missing' do
    let(:location) { nil }

    it 'leaves the game unknown instead of assuming home' do
      described_class.new(game).call

      expect(game.reload).to have_attributes(
        venue_type: 'unknown',
        venue_source: nil,
        venue_confidence: 'unknown',
        neutral: nil
      )
    end
  end
end
