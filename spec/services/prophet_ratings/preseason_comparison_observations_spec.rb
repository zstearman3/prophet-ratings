# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::PreseasonComparisonObservations do
  include ActiveSupport::Testing::TimeHelpers

  let(:version) { RatingsConfigVersion.publish! }
  let(:season) { create(:season, start_date: Date.new(2025, 11, 1), end_date: Date.new(2026, 4, 1)) }
  let(:home) { create(:team_season, season:) }
  let(:away) { create(:team_season, season:) }
  let(:date) { Date.new(2025, 11, 20) }
  let(:history) { [result_on(2), result_on(3)] }

  before do
    unless ENV['REAL_COMPARISON_SOLVER'] == '1'
      allow(StatisticsUtils).to receive(:solve_least_squares_with_python) do |rows, _targets, **|
        Array.new(rows.first.size, 0.0)
      end
    end
  end

  def result_on(day)
    timestamp = Time.utc(2025, 11, day, 23)
    game = create(:game, season:, start_time: timestamp, status: :final, venue_type: :neutral,
                         home_team_score: 80, away_team_score: 70, possessions: 70, minutes: 40,
                         created_at: timestamp, updated_at: timestamp)
    create(:team_game, game:, team_season: home, team: home.team, home: true, offensive_rating: 100,
                       created_at: timestamp, updated_at: timestamp)
    create(:team_game, game:, team_season: away, team: away.team, home: false, offensive_rating: 100,
                       created_at: timestamp, updated_at: timestamp)
    game.reload
  end

  def report(games = history, day = date)
    described_class.new(games:, date: day, version:).call
  end

  it 'rebuilds core observations with the real solver optionally and ignores contaminated live values' do
    first = report
    expect(first[:ratings].values).to all(include('adj_offensive_efficiency' => be_within(0.0001).of(100),
                                                  'adj_defensive_efficiency' => be_within(0.0001).of(100),
                                                  'adj_pace' => be_within(0.0001).of(70)))
    home.update!(adj_offensive_efficiency: 999, pace: 999)
    season.update!(average_efficiency: 999, average_pace: 999)
    expect(report(history.reverse)).to eq(first)
    expect(TeamRatingSnapshot.count).to eq(0)
    expect(Prediction.count).to eq(0)
  end

  it 'excludes late revisions and creation, and leaves zero/one-game teams at their priors' do
    history.first.update!(updated_at: Game.schedule_day_range(date).begin)
    first = report
    expect(first[:ratings]).to eq({})
    expect(first[:excluded_result_game_ids]).to eq([history.first.id])
    history.last.away_team_game.update!(created_at: Game.schedule_day_range(date).begin)
    expect(report[:counts]).to eq({})
  end

  it 'bounds even explicitly supplied same-day or future results' do
    expect(report(history, Date.new(2025, 11, 3))[:result_game_ids]).to eq([history.first.id])
    expect(report(history, Date.new(2025, 11, 1))[:counts]).to eq({})
  end

  it 'solves independently reasoned offense/defense offsets when using real Python' do
    history.each do |game|
      travel_to(game.start_time + 2.hours) do
        game.home_team_game.update!(offensive_rating: 110)
        game.away_team_game.update!(offensive_rating: 90)
      end
    end
    unless ENV['REAL_COMPARISON_SOLVER'] == '1'
      allow(StatisticsUtils).to receive(:solve_least_squares_with_python).and_return([5, -5, -5, 5], [0, 0, 0, 0])
    end
    # Equations hO+aD=10, aO+hD=-10, hO+aO=0. Ridge shrinks the min-norm +/-5 by <.002.
    expect(report[:ratings].fetch(home.team_id)).to include('adj_offensive_efficiency' => be_within(0.002).of(105),
                                                            'adj_defensive_efficiency' => be_within(0.002).of(95))
  end

  it 'uses recency-weighted effective counts and refuses missing raw inputs' do
    # Through Nov 19: ages 17 and 16; weights 1 - age/60 * .25.
    expect(report[:effective_counts].values).to all(be_within(0.0001).of(1.8625))
    history.first.away_team_game.update!(offensive_rating: nil)
    expect(report[:ratings]).to eq({})
    expect(report([])[:counts]).to eq({})
  end

  it 'retains priors for qualified teams without any qualified opponent rows' do
    connected = history
    isolated = create(:team_season, season:)
    disconnected = [4, 5].map do |day|
      result = result_on(day)
      opponent = create(:team_season, season:)
      travel_to(result.start_time + 1.hour) do
        result.home_team_game.update!(team_season: isolated, team: isolated.team)
        result.away_team_game.update!(team_season: opponent, team: opponent.team)
      end
      result.reload
    end
    result = report(connected + disconnected)
    expect(result[:counts].fetch(isolated.team_id)).to eq(2)
    expect(result[:ratings].keys).to contain_exactly(home.team_id, away.team_id)
    expect(result[:ratings]).to eq(report(connected)[:ratings])
  end
end
