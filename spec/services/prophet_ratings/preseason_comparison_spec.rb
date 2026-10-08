# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::PreseasonComparison do
  let(:version) { create(:ratings_config_version, name: 'historical') }
  let(:previous) { create(:season, year: 2025, start_date: Date.new(2024, 11, 1), end_date: Date.new(2025, 4, 10)) }
  let(:season) { create(:season, year: 2026, start_date: Date.new(2025, 11, 1), end_date: Date.new(2026, 4, 10)) }
  let(:home) { create(:team_season, season:) }
  let(:away) { create(:team_season, season:) }
  let(:game) do
    create(:game, season:, start_time: Time.utc(2025, 11, 2, 22), status: :final,
                  home_team_score: 80, away_team_score: 70, venue_type: :neutral)
  end
  let(:comparison) { described_class.new(years: [2026], source_config_name: version.name) }

  def source(team, offense)
    old_team_season = create(:team_season, season: previous, team:)
    create(:team_rating_snapshot, team_season: old_team_season, ratings_config_version: version,
                                  snapshot_date: previous.end_date, adj_offensive_efficiency: offense,
                                  adj_defensive_efficiency: 100, adj_pace: 69.5,
                                  created_at: Time.utc(2025, 6, 1), updated_at: Time.utc(2025, 6, 1))
  end

  before do
    create(:team_game, game:, team_season: home, team: home.team, home: true)
    create(:team_game, game:, team_season: away, team: away.team, home: false)
  end

  it 'compares fixed candidates on pre-opening stored transitions and ignores mutable season averages' do
    source(home.team, 120)
    source(away.team, 100)
    report = comparison.call
    baseline = report[:seasons].first[:candidates].fetch(0.85)
    # Source mean = 110, priors = 118.5 and 101.5. Scores = 78.54 and 66.72.
    expect(baseline[:margin_mae]).to be_within(0.0001).of(1.82)
    expect(baseline[:total_mae]).to be_within(0.0001).of(4.74)
    expect(baseline[:brier_score]).to be_between(0, 1)
    season.update!(average_efficiency: 999, average_pace: 999)
    expect(comparison.call).to eq(report)
    expect(Prediction.count).to eq(0)
  end

  it 'rejects backdated snapshots created or revised after opening and does not substitute live history' do
    source(home.team, 120).update!(updated_at: Time.utc(2025, 11, 1, 4))
    source(away.team, 100).update!(created_at: Time.utc(2025, 11, 2))
    result = comparison.call[:seasons].first
    expect(result).to include(source_teams: 0, eligible_games: 0, excluded_games: 1)
    expect(result[:candidates].fetch(0.85)[:brier_score]).to be_nil
  end

  it 'excludes unknown venues, ties and games outside the first 30 Eastern schedule dates' do
    source(home.team, 120)
    source(away.team, 100)
    game.update!(venue_type: :unknown)
    expect(comparison.call[:seasons].first[:eligible_games]).to eq(0)
    game.update!(venue_type: :neutral, away_team_score: 80)
    expect(comparison.call[:seasons].first[:eligible_games]).to eq(0)
    game.update!(start_time: Time.utc(2025, 12, 1, 5))
    expect(comparison.call[:seasons].first[:opening_final_games]).to eq(0)
  end
end
