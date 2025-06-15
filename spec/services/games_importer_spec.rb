require 'rails_helper'

RSpec.describe Importer::GamesImporter do
  let(:season) { Season.create!(year: 2025, start_date: '2024-11-01', end_date: '2025-04-10', name: '2024-25') }
  let(:home_team) { Team.create!(school: 'Home School', nickname: 'Home', slug: 'home', url: 'http://home.com') }
  let(:away_team) { Team.create!(school: 'Away School', nickname: 'Away', slug: 'away', url: 'http://away.com') }
  let!(:home_team_season) { TeamSeason.create!(team: home_team, season: season) }
  let!(:away_team_season) { TeamSeason.create!(team: away_team, season: season) }
  let(:date) { Date.new(2025, 1, 1) }

  let(:row) do
    {
      home_team: home_team.school,
      away_team: away_team.school,
      date: date,
      home_team_score: 100,
      away_team_score: 90,
      location: 'Home Arena',
      url: 'http://example.com/game',
      home_team_stats: {},
      away_team_stats: {}
    }
  end

  it 'creates a new game for unique teams and date' do
    expect {
      described_class.import([row])
    }.to change(Game, :count).by(1)
    game = Game.last
    expect(game.home_team_name).to eq home_team.school
    expect(game.away_team_name).to eq away_team.school
    expect(game.start_time.to_date).to eq date
  end

  it 'does not create a duplicate game for the same teams and date' do
    described_class.import([row])
    expect {
      described_class.import([row])
    }.not_to change(Game, :count)
  end

  it 'creates a second game for a true double header (same teams, same day, different time)' do
    described_class.import([row])
    row2 = row.merge(date: date.to_datetime.change({ hour: 20 }))
    expect {
      described_class.import([row2])
    }.to change(Game, :count).by(1)
  end
end
