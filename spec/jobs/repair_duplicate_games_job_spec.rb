# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RepairDuplicateGamesJob do
  let(:season) { create(:season, year: 2026, start_date: Date.new(2025, 11, 1), end_date: Date.new(2026, 4, 10)) }

  def create_game(attrs)
    build(:game, attrs).tap { |game| game.save!(validate: false) }
  end

  it 'runs duplicate repair in apply mode for a season' do
    create_game(
      season:,
      start_time: Game::SCHEDULE_TIME_ZONE.parse('2026-01-01 7:00pm'),
      home_team_name: 'Home',
      away_team_name: 'Away',
      url: '/cbb/boxscores/2026-01-01-00-home.html'
    )
    create_game(
      season:,
      status: :final,
      start_time: Game::SCHEDULE_TIME_ZONE.parse('2026-01-01 7:00pm'),
      home_team_name: 'Home',
      away_team_name: 'Away',
      url: '/cbb/boxscores/2026-01-01-00-home.html'
    )

    described_class.perform_now(season_id: season.id, apply: true)

    expect(Game.count).to eq(1)
  end

  it 'defaults to dry-run mode' do
    create_game(
      season:,
      start_time: Game::SCHEDULE_TIME_ZONE.parse('2026-01-01 7:00pm'),
      home_team_name: 'Home',
      away_team_name: 'Away',
      url: '/cbb/boxscores/2026-01-01-00-home.html'
    )
    create_game(
      season:,
      start_time: Game::SCHEDULE_TIME_ZONE.parse('2026-01-01 7:00pm'),
      home_team_name: 'Home',
      away_team_name: 'Away',
      url: '/cbb/boxscores/2026-01-01-00-home.html'
    )

    described_class.perform_now(season_id: season.id)

    expect(Game.count).to eq(2)
  end
end
