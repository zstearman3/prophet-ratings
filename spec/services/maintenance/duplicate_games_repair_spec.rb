# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maintenance::DuplicateGamesRepair do
  let(:season) { create(:season, year: 2025, start_date: '2024-11-01', end_date: '2025-04-10') }
  let(:home_team) { create(:team, school: 'Home School') }
  let(:away_team) { create(:team, school: 'Away School') }
  let(:home_team_season) { create(:team_season, team: home_team, season:) }
  let(:away_team_season) { create(:team_season, team: away_team, season:) }
  let(:output) { StringIO.new }

  def create_game(attrs)
    build(:game, attrs).tap { |game| game.save!(validate: false) }
  end

  it 'reports duplicate groups without mutating records by default' do
    create_game(
      season:,
      start_time: Time.zone.local(2025, 1, 1),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: '/cbb/boxscores/2025-01-01-00-home.html'
    )
    create_game(
      season:,
      start_time: Game::SCHEDULE_TIME_ZONE.parse('2025-01-01 9:00pm'),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: '/cbb/boxscores/2025-01-01-00-home.html'
    )

    result = described_class.new(output:).call

    expect(result.applied).to be(false)
    expect(result.groups.size).to eq(1)
    expect(result.deleted_game_ids).to be_empty
    expect(Game.count).to eq(2)
    expect(output.string).to include('DRY RUN')
  end

  it 'applies repairs by keeping the strongest survivor and deleting duplicates' do
    scheduled_duplicate = create_game(
      season:,
      status: :scheduled,
      start_time: Time.zone.local(2025, 1, 1),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: '/cbb/boxscores/2025-01-01-00-home.html'
    )
    final_survivor = create_game(
      season:,
      status: :final,
      start_time: Game::SCHEDULE_TIME_ZONE.parse('2025-01-01 9:00pm'),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: '/cbb/boxscores/2025-01-01-00-home.html',
      venue_type: 'home',
      venue_confidence: 'confirmed',
      venue_name: 'Home Arena'
    )
    create(:team_game, game: final_survivor, team: home_team, team_season: home_team_season, home: true)
    create(:team_game, game: final_survivor, team: away_team, team_season: away_team_season, home: false)

    result = described_class.new(apply: true, output:).call

    expect(result.applied).to be(true)
    expect(result.deleted_game_ids).to contain_exactly(scheduled_duplicate.id)
    expect(Game.exists?(scheduled_duplicate.id)).to be(false)
    expect(Game.exists?(final_survivor.id)).to be(true)
  end

  it 'reassigns safe dependent records before deleting a duplicate' do
    survivor = create_game(
      season:,
      status: :final,
      start_time: Game::SCHEDULE_TIME_ZONE.parse('2025-01-01 9:00pm'),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: '/cbb/boxscores/2025-01-01-00-home.html'
    )
    duplicate = create_game(
      season:,
      status: :scheduled,
      start_time: Time.zone.local(2025, 1, 1),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: '/cbb/boxscores/2025-01-01-00-home.html'
    )
    game_odd = create(:game_odd, game: duplicate, fetched_at: Time.current)
    bookmaker_odd = create(:bookmaker_odd, game: duplicate, bookmaker: 'DraftKings', fetched_at: Time.current, market: 'h2h')
    create(:team_game, game: duplicate, team: home_team, team_season: home_team_season, home: true)
    create(:team_game, game: duplicate, team: away_team, team_season: away_team_season, home: false)

    described_class.new(apply: true, output:).call

    expect(game_odd.reload.game).to eq(survivor)
    expect(bookmaker_odd.reload.game).to eq(survivor)
    expect(survivor.reload.home_team_game.team).to eq(home_team)
    expect(survivor.away_team_game.team).to eq(away_team)
    expect(Game.exists?(duplicate.id)).to be(false)
  end

  it 'detects reversed neutral duplicates by unordered team pair and schedule date' do
    create_game(
      season:,
      start_time: Game::SCHEDULE_TIME_ZONE.parse('2025-01-01 9:00pm'),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: 'https://www.sports-reference.com/cbb/boxscores/index.cgi?month=1&day=1&year=2025',
      venue_type: 'neutral',
      neutral: true
    )
    create_game(
      season:,
      start_time: Game::SCHEDULE_TIME_ZONE.parse('2025-01-01 9:30pm'),
      home_team_name: away_team.school,
      away_team_name: home_team.school,
      url: 'https://www.sports-reference.com/cbb/boxscores/index.cgi?month=1&day=1&year=2025',
      venue_type: 'neutral',
      neutral: true
    )

    result = described_class.new(output:).call

    expect(result.groups.size).to eq(1)
    expect(result.groups.first.games.map(&:id).size).to eq(2)
  end

  it 'does not group unrelated games by shared daily schedule URL' do
    create_game(
      season:,
      start_time: Game::SCHEDULE_TIME_ZONE.parse('2025-01-01 7:00pm'),
      home_team_name: home_team.school,
      away_team_name: away_team.school,
      url: 'https://www.sports-reference.com/cbb/boxscores/index.cgi?month=1&day=1&year=2025'
    )
    create_game(
      season:,
      start_time: Game::SCHEDULE_TIME_ZONE.parse('2025-01-01 9:00pm'),
      home_team_name: 'Other Home',
      away_team_name: 'Other Away',
      url: 'https://www.sports-reference.com/cbb/boxscores/index.cgi?month=1&day=1&year=2025'
    )

    result = described_class.new(output:).call

    expect(result.groups).to be_empty
  end
end
