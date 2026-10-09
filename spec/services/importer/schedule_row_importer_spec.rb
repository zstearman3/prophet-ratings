# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Importer::ScheduleRowImporter do
  let(:season) { create(:season, year: 2027) }
  let(:date) { season.start_date }
  let(:row) do
    { home_team: 'Home Team', away_team: 'Away Team', date:, url: '/cbb/boxscores/index.cgi?day=1',
      home_team_stats: {}, away_team_stats: {} }
  end

  def import_row(payload)
    described_class.new(season:, row: payload).call
  end

  it 'preserves a stable game identity and reports time updates on repeated runs' do
    first = import_row(row)
    changed = import_row(row.merge(date: Game.schedule_time_for(date) + 12.hours))
    stable = import_row(row.merge(date: Game.schedule_time_for(date) + 12.hours))
    expect(Game.count).to eq(1)
    expect(changed).to include(game_id: first[:game_id], outcome: 'updated')
    expect(changed[:changes]).to have_key('start_time')
    expect(stable[:outcome]).to eq('unchanged')
    expect(stable[:unmatched]).to eq(['Home Team', 'Away Team'])
  end

  it 'moves a game with a unique game URL and retains its ID and manual venue' do
    game = create(:game, season:, start_time: Game.schedule_time_for(date), status: :scheduled,
                         url: '/unique.html', venue_name: 'Manual Arena', venue_confidence: 'manual')
    result = import_row(row.merge(url: game.url, date: date + 1.day, venue_name: 'Source Arena'))
    expect(result).to include(game_id: game.id, outcome: 'updated')
    expect(game.reload.schedule_date).to eq(date + 1.day)
    expect(game.venue_name).to eq('Manual Arena')
    expect(Game.count).to eq(1)
  end

  it 'reports possible moves without guessing when only teams match across dates' do
    previous = import_row(row)
    result = import_row(row.merge(date: date + 1.day))
    expect(result[:possible_move_ids]).to eq([previous[:game_id]])
    expect(Game.count).to eq(2)
    expect(Game.find(previous[:game_id]).schedule_date).to eq(date)
  end

  it 'reports duplicate URLs as ambiguous without modifying either game' do
    first = create(:game, season:, start_time: Game.schedule_time_for(date), status: :scheduled, url: '/duplicate.html')
    second = create(:game, season:, start_time: Game.schedule_time_for(date + 1.day), status: :scheduled, url: first.url)
    result = import_row(row.merge(url: first.url, date: date + 2.days))
    expect(result).to include(outcome: 'ambiguous', candidate_ids: [first.id, second.id])
    expect(first.reload.schedule_date).to eq(date)
    expect(second.reload.schedule_date).to eq(date + 1.day)
  end

  it 'refuses a URL belonging to a different season' do
    game = create(:game, url: '/other-season.html')
    result = import_row(row.merge(url: game.url))
    expect(result).to include(outcome: 'ambiguous', candidate_ids: [game.id])
    expect(season.games.count).to eq(0)
  end

  it 'protects all completed game attributes and associations from a partial row' do
    game = create(:game, season:, start_time: Game.schedule_time_for(date), url: '/final.html',
                         home_team_score: 80, away_team_score: 70, minutes: 40, possessions: 65)
    team_game = create(:team_game, game:, home: true, points: 80)
    before = game.attributes
    associations = team_game.attributes
    result = import_row(row.merge(url: game.url, date: date + 1.day, home_team_score: nil))
    expect(result[:outcome]).to eq('protected')
    expect(game.reload.attributes).to eq(before)
    expect(team_game.reload.attributes).to eq(associations)
  end

  it 'rejects rows outside the explicit target season' do
    expect { import_row(row.merge(date: season.end_date + 1.day)) }.to raise_error(ArgumentError, /outside target season/)
    expect(Game.count).to eq(0)
  end

  it 'retains a reliable URL through placeholder refresh so a later date move reuses the game' do
    game = create(:game, season:, start_time: Game.schedule_time_for(date), status: :scheduled, url: '/stable.html')
    import_row(row)
    expect(game.reload.url).to eq('/stable.html')
    moved = import_row(row.merge(date: date + 1.day, url: '/stable.html'))
    expect(moved).to include(game_id: game.id, outcome: 'updated')
    expect(game.reload.schedule_date).to eq(date + 1.day)
    expect(Game.count).to eq(1)
  end
end
