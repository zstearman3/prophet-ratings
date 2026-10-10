# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::PreseasonComparison do
  before do
    RatingsConfigVersion.publish!
    create(:team_game, game:, team_season: home, team: home.team, home: true)
    create(:team_game, game:, team_season: away, team: away.team, home: false)
  end

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

  it 'rejects coaching models explicitly because the preregistered benchmark has no archived coaching inputs' do
    source(home.team, 120)
    source(away.team, 100)
    payload = RatingsConfigVersion.authored_config.merge(bundle_name: 'coaching-comparison')
    payload[:preseason][:coaching] = { formula: 'relative_pace_v1', weight: 0.1, max_adjustment: 0.5 }
    selected = RatingsConfigVersion.publish!(payload)
    benchmark = described_class.new(years: [2026], source_config_name: version.name, ratings_config_version: selected)
    expect { benchmark.call }.to raise_error(ArgumentError, /select a model without preseason.coaching.*archived reviewed inputs/)
    single_season = ProphetRatings::PreseasonComparisonSeason.new(season:, source_version: version, ratings_config_version: selected)
    expect { single_season.call }.to raise_error(ArgumentError, /archived reviewed inputs/)
    expect([Prediction.count, PreseasonPrior.count]).to eq([0, 0])
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

  it 'reports one row per common game/candidate and rebuilds only eligible prior-day results' do
    source(home.team, 120)
    source(away.team, 100)
    timestamp = Time.utc(2025, 11, 3, 23)
    game.update!(possessions: 70, minutes: 40, created_at: timestamp, updated_at: timestamp)
    [game.home_team_game, game.away_team_game].each do |side|
      side.update!(offensive_rating: 100, created_at: timestamp, updated_at: timestamp)
    end
    later = create(:game, season:, start_time: Time.utc(2025, 11, 19, 22), status: :final, venue_type: :neutral,
                          home_team_score: 80, away_team_score: 70)
    create(:team_game, game: later, team_season: home, team: home.team, home: true)
    create(:team_game, game: later, team_season: away, team: away.team, home: false)
    sequence = comparison.call[:seasons].first[:sequential]
    expect(sequence[:candidates].values.map { |candidate| candidate[:forecasts].pluck(:game_id) }).to all(eq([game.id, later.id]))
    expect(sequence[:observations].fetch('2025-11-02')[:counts]).to eq({})
    expect(sequence[:observations].fetch('2025-11-19')[:result_game_ids]).to eq([game.id])
    expect(sequence[:missing_second_year_teams]).to contain_exactly(home.team_id, away.team_id)
    expect(sequence[:candidates].values.map { |candidate| candidate[:by_prior_game_count].keys }).to all(eq([0, 1]))
  end

  it 'reserves the latest eligible season for held-out evaluation without selecting coefficients' do
    expect(described_class.split_description([{ year: 2024, eligible_games: 0 }, { year: 2025, eligible_games: 2 },
                                              { year: 2026, eligible_games: 3 }])).to include(tuning: [2025], evaluation: [2026])
  end
end
