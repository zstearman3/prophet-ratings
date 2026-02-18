# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Importer::GamesImporter do
  let(:season) { Season.create!(year: 2025, start_date: '2024-11-01', end_date: '2025-04-10', name: '2024-25') }
  let(:home_team) { Team.create!(school: 'Home School', nickname: 'Home', slug: 'home', url: 'http://home.com') }
  let(:away_team) { Team.create!(school: 'Away School', nickname: 'Away', slug: 'away', url: 'http://away.com') }
  let(:home_team_season) { TeamSeason.create!(team: home_team, season:) }
  let(:away_team_season) { TeamSeason.create!(team: away_team, season:) }
  let(:home_alias) { TeamAlias.create!(team: home_team, value: home_team.school, source: 'sports_reference') }
  let(:away_alias) { TeamAlias.create!(team: away_team, value: away_team.school, source: 'sports_reference') }
  let(:date) { Date.new(2025, 1, 1) }

  let(:home_team_stats) do
    {
      minutes: 200,
      field_goals_made: 35,
      field_goals_attempted: 68,
      two_pt_made: 24,
      two_pt_attempted: 40,
      three_pt_made: 11,
      three_pt_attempted: 28,
      free_throws_made: 19,
      free_throws_attempted: 24,
      offensive_rebounds: 9,
      defensive_rebounds: 26,
      rebounds: 35,
      assists: 16,
      steals: 7,
      blocks: 4,
      turnovers: 11,
      fouls: 17,
      points: 100
    }
  end

  let(:away_team_stats) do
    {
      minutes: 200,
      field_goals_made: 31,
      field_goals_attempted: 65,
      two_pt_made: 21,
      two_pt_attempted: 39,
      three_pt_made: 10,
      three_pt_attempted: 26,
      free_throws_made: 18,
      free_throws_attempted: 22,
      offensive_rebounds: 10,
      defensive_rebounds: 24,
      rebounds: 34,
      assists: 14,
      steals: 6,
      blocks: 3,
      turnovers: 12,
      fouls: 19,
      points: 90
    }
  end

  let(:row) do
    {
      home_team: home_team.school,
      away_team: away_team.school,
      date:,
      home_team_score: 100,
      away_team_score: 90,
      location: 'Home Arena',
      url: 'http://example.com/game',
      home_team_stats: {},
      away_team_stats: {},
      season_id: season.id
    }
  end

  let(:completed_row) do
    row.merge(
      home_team_stats: home_team_stats,
      away_team_stats: away_team_stats
    )
  end

  before do
    home_team_season
    away_team_season
    home_alias
    away_alias
  end

  it 'creates a new game for unique teams and date' do
    expect do
      described_class.import([row])
    end.to change(Game, :count).by(1)
  end

  it 'assigns correct attributes to the new game' do
    described_class.import([row])
    game = Game.last
    expect(game.home_team_name).to eq home_team.school
    expect(game.away_team_name).to eq away_team.school
    expect(game.start_time.to_date).to eq date
  end

  it 'does not create a duplicate game for the same teams and date' do
    described_class.import([row])
    expect do
      described_class.import([row])
    end.not_to change(Game, :count)
  end

  it 'keeps incomplete games scheduled' do
    described_class.import([row])
    expect(Game.last).to be_scheduled
  end

  it 'finalizes complete games' do
    described_class.import([completed_row])
    game = Game.last
    expect(game).to be_final
    expect(game.minutes).to be_present
  end

  it 'keeps a game scheduled when derived pace cannot be computed' do
    invalid_completed_row = completed_row.deep_dup
    invalid_completed_row[:home_team_stats][:minutes] = 0
    invalid_completed_row[:away_team_stats][:minutes] = 0

    expect { described_class.import([invalid_completed_row]) }.not_to raise_error

    game = Game.last
    expect(game).to be_scheduled
    expect(game.minutes).to be_nil
    expect(game.pace).to be_nil
  end

  it 'does not downgrade an existing final game when an incomplete row is imported later' do
    described_class.import([completed_row])
    game = Game.last

    described_class.import([row.merge(home_team_score: nil, away_team_score: nil)])

    expect(game.reload).to be_final
    expect(game.home_team_score).to eq(100)
    expect(game.away_team_score).to eq(90)
  end

  it 'downgrades a broken legacy final game to scheduled when incoming data is incomplete' do
    described_class.import([completed_row])
    game = Game.last
    game.update!(minutes: nil, possessions: nil) # simulate bad historical finalization

    described_class.import([row.merge(home_team_score: nil, away_team_score: nil)])

    expect(game.reload).to be_scheduled
  end

  it 'creates a second game for a true double header (same teams, same day, different time)' do
    skip('double header logic not implemented yet')
    # This is currently not supported due to strict uniqueness validation by teams and date.
    # If double header support is needed, update the model validation and remove this skip.
    row2 = row.merge(date: date.to_datetime.change({ hour: 20 }))
    described_class.import([row])
    expect do
      described_class.import([row2])
    end.to change(Game, :count).by(1)
  end
end
