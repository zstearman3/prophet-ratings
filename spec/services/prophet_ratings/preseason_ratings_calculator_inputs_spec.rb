# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::PreseasonRatingsCalculator do
  before { RatingsConfigVersion.publish! }

  def count_prior_team_season_queries
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      sql = payload[:sql]
      queries << sql if sql.lstrip.start_with?('SELECT') && sql.include?('FROM "team_seasons"') &&
                        sql.include?('"team_seasons"."season_id"') && sql.include?('"team_seasons"."team_id"')
    end
    result = yield
    [result, queries.length]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  def reviewed_version(bundle_name)
    config = RatingsConfigVersion.authored_config.deep_dup
    config[:bundle_name] = bundle_name
    config[:preseason].merge!(YAML.load_file(Rails.root.join('config/examples/reviewed_efficiency_r3.yml')).deep_symbolize_keys)
    RatingsConfigVersion.publish!(config)
  end

  def formula_outputs(inputs, config = inputs[:configuration])
    ProphetRatings::PreseasonPriorFormula.new(inputs, config).call
  end

  def create_previous_team_season(team_season, previous, **stats)
    create(:team_season, season: previous, team: team_season.team, **stats)
  end

  it 'builds legacy inputs from the explicitly supplied prior season' do
    season = create(:season, year: 2027)
    previous = create(
      :season,
      year: 2026,
      average_efficiency: 106,
      average_pace: 69,
      avg_adj_offensive_efficiency: 107,
      avg_adj_defensive_efficiency: 104
    )
    team_season = create(:team_season, season:)
    previous_team_season = create(:team_season, season: previous, team: team_season.team,
                                                adj_offensive_efficiency: 112, adj_defensive_efficiency: 99,
                                                adj_pace: 67)
    calculator = described_class.new(season)

    inputs = calculator.send(:legacy_inputs, team_season, previous)

    expect(inputs[:previous_season]).to include(id: previous.id, updated_at: previous.updated_at.iso8601(6),
                                                attributes: previous.attributes)
    expect(inputs[:previous_team_season][:id]).to eq(previous_team_season.id)
    expect(inputs[:previous_team_season][:updated_at]).to eq(previous_team_season.updated_at.iso8601(6))
    expect(inputs[:previous_team_season][:attributes]).to eq(previous_team_season.attributes)
    expect(inputs[:baselines]).to include('adj_offensive_efficiency' => 107,
                                          'adj_defensive_efficiency' => 104, 'adj_pace' => 69)
  end

  it 'falls back independently for missing offense, defense, pace, and team history' do
    season = create(:season, year: 2027)
    previous = create(
      :season,
      year: 2026,
      average_efficiency: 106,
      average_pace: 69,
      avg_adj_offensive_efficiency: 107,
      avg_adj_defensive_efficiency: nil
    )
    team_season = create(:team_season, season:)
    previous_team_season = create_previous_team_season(
      team_season, previous, adj_offensive_efficiency: 112, adj_defensive_efficiency: nil, adj_pace: 67
    )
    calculator = described_class.new(season)

    inputs = calculator.preview_inputs(team_season)

    expect(formula_outputs(inputs)).to include(
      'preseason_adj_offensive_efficiency' => 111.25,
      'preseason_adj_defensive_efficiency' => 106.0,
      'preseason_adj_pace' => 67.3
    )

    previous.update!(avg_adj_offensive_efficiency: nil, avg_adj_defensive_efficiency: 103)
    previous_team_season.update!(adj_offensive_efficiency: nil, adj_defensive_efficiency: 101, adj_pace: nil)
    inputs = calculator.preview_inputs(team_season)
    expect(inputs[:baselines]).to include('adj_offensive_efficiency' => 106, 'adj_defensive_efficiency' => 103)
    expect(formula_outputs(inputs)).to include(
      'preseason_adj_offensive_efficiency' => 106.0,
      'preseason_adj_defensive_efficiency' => 101.3,
      'preseason_adj_pace' => 69.0
    )
  end

  it 'uses selected efficiency and pace fallbacks when the prior season is absent' do
    season = create(:season, year: 2027)
    team_season = create(:team_season, season:)
    config = RatingsConfigVersion.authored_config.deep_dup
    config[:bundle_name] = 'explicit-prior-selected-fallbacks'
    config[:preseason][:fallback_efficiency] = 111.0
    config[:preseason][:fallback_pace] = 72.0
    version = RatingsConfigVersion.publish!(config)

    inputs = described_class.new(season, ratings_config_version: version).preview_inputs(team_season)

    expect(inputs[:previous_season]).to be_nil
    expect(inputs[:previous_values]).to eq('adj_offensive_efficiency' => nil,
                                           'adj_defensive_efficiency' => nil, 'adj_pace' => nil)
    expect(inputs[:baselines]).to eq('adj_offensive_efficiency' => 111.0,
                                     'adj_defensive_efficiency' => 111.0, 'adj_pace' => 72.0)
    expect(formula_outputs(inputs, version.config)).to eq(
      'preseason_adj_offensive_efficiency' => 111.0,
      'preseason_adj_defensive_efficiency' => 111.0,
      'preseason_adj_pace' => 72.0
    )
  end

  it 'uses selected fallbacks for present prior data with missing averages and stats' do
    season = create(:season, year: 2027)
    team_season = create(:team_season, season:)
    previous = create(
      :season,
      year: 2026,
      average_efficiency: nil,
      average_pace: nil,
      avg_adj_offensive_efficiency: nil,
      avg_adj_defensive_efficiency: nil
    )
    previous_team_season = create(:team_season, season: previous, team: team_season.team,
                                                adj_offensive_efficiency: nil, adj_defensive_efficiency: nil,
                                                adj_pace: nil)
    config = RatingsConfigVersion.authored_config.deep_dup
    config[:bundle_name] = 'explicit-prior-missing-selected-fallbacks'
    config[:preseason][:fallback_efficiency] = 111.0
    config[:preseason][:fallback_pace] = 72.0
    version = RatingsConfigVersion.publish!(config)

    inputs = described_class.new(season, ratings_config_version: version).preview_inputs(team_season)

    expect(inputs[:previous_season]).to include(id: previous.id)
    expect(inputs[:previous_team_season]).to include(id: previous_team_season.id)
    expect(inputs[:baselines]).to eq('adj_offensive_efficiency' => 111.0,
                                     'adj_defensive_efficiency' => 111.0, 'adj_pace' => 72.0)
    expect(inputs[:previous_values]).to eq('adj_offensive_efficiency' => nil,
                                           'adj_defensive_efficiency' => nil, 'adj_pace' => nil)
  end

  it 'retains a zero efficiency average as a valid baseline' do
    previous = create(:season, year: 2026, average_efficiency: 0)
    calculator = described_class.new(create(:season, year: 2027))

    expect(calculator.send(:average_for_stat, 'adj_offensive_efficiency', previous)).to eq(0)
    expect(calculator.send(:average_for_stat, 'adj_defensive_efficiency', previous)).to eq(0)
  end

  it 'resolves prior history afresh for each preview without adding source lookups' do
    season = create(:season, year: 2027)
    team_season = create(:team_season, season:)
    calculator = described_class.new(season)
    allow(Season).to receive(:find_by).and_call_original

    first = calculator.preview_inputs(team_season)
    previous = create(:season, year: 2026, average_efficiency: 106, average_pace: 69)
    second = calculator.preview_inputs(team_season)

    previous.update!(average_efficiency: 109, average_pace: 71)
    create(:team_season, season: previous, team: team_season.team,
                         adj_offensive_efficiency: 112, adj_defensive_efficiency: 99, adj_pace: 67)
    third, query_count = count_prior_team_season_queries { calculator.preview_inputs(team_season) }
    actual = [
      first[:baselines].slice('adj_offensive_efficiency', 'adj_pace'),
      [second[:previous_season][:id], second[:baselines].slice('adj_offensive_efficiency', 'adj_pace')],
      [third[:baselines].slice('adj_offensive_efficiency', 'adj_pace'), third[:previous_values]], query_count
    ]
    expected = [
      { 'adj_offensive_efficiency' => 105.5, 'adj_pace' => 69.5 },
      [previous.id, { 'adj_offensive_efficiency' => 106, 'adj_pace' => 69 }],
      [{ 'adj_offensive_efficiency' => 109, 'adj_pace' => 71 },
       { 'adj_offensive_efficiency' => 112, 'adj_defensive_efficiency' => 99, 'adj_pace' => 67 }],
      1
    ]
    expect(actual).to eq(expected)
    expect(Season).to have_received(:find_by).with(year: 2026).exactly(3).times
  end

  it 'keeps the coaching target anchor on the captured pace baseline' do
    season = create(:season, year: 2027)
    team_season = create(:team_season, season:)
    config = RatingsConfigVersion.authored_config.deep_dup
    config[:bundle_name] = 'explicit-prior-coaching-anchor'
    config[:preseason][:fallback_pace] = 72.0
    config[:preseason][:coaching] = { formula: 'relative_pace_v2', weight: 0.5 }
    version = RatingsConfigVersion.publish!(config)
    CoachingReview.create!(year: 2027, ready: true)

    inputs = described_class.new(season, ratings_config_version: version).preview_inputs(team_season)

    expect(inputs[:previous_season]).to be_nil
    expect(inputs[:baselines]['adj_pace']).to eq(72)
    expect(inputs.dig(:coaching, :target_anchor)).to eq(72)
  end

  it 'keeps reviewed inputs explicit when the prior season has no matching team row' do
    season = create(:season, year: 2027)
    team_season = create(:team_season, season:)
    previous = create(
      :season,
      year: 2026,
      average_efficiency: 106,
      average_pace: 69,
      avg_adj_offensive_efficiency: 107,
      avg_adj_defensive_efficiency: nil
    )
    version = reviewed_version('explicit-prior-reviewed-inputs')

    calculator = described_class.new(season, ratings_config_version: version)
    inputs = calculator.preview_inputs(team_season)

    expected_inputs = {
      contract: 'preseason-v3-reviewed-efficiency',
      previous_season: { id: previous.id, updated_at: previous.updated_at.iso8601(6),
                         attributes: previous.attributes },
      previous_team_season: nil,
      previous_values: { 'adj_offensive_efficiency' => nil, 'adj_defensive_efficiency' => nil, 'adj_pace' => nil },
      baselines: { 'adj_offensive_efficiency' => 107.0, 'adj_defensive_efficiency' => 106.0, 'adj_pace' => 69.0 },
      baseline_sources: { 'adj_offensive_efficiency' => 'previous_season.avg_adj_offensive_efficiency',
                          'adj_defensive_efficiency' => 'previous_season.average_efficiency',
                          'adj_pace' => 'previous_season.average_pace' }
    }
    expect(inputs.slice(*expected_inputs.keys)).to eq(expected_inputs)
    expect(ProphetRatings::PreseasonPriorFormula.new(inputs, version.config).call).to eq(
      'preseason_adj_offensive_efficiency' => 107.0,
      'preseason_adj_defensive_efficiency' => 106.0,
      'preseason_adj_pace' => 69.0
    )
  end

  it 'uses selected reviewed fallbacks when the prior Season is missing' do
    season = create(:season, year: 2027)
    team_season = create(:team_season, season:)
    version = reviewed_version('explicit-prior-reviewed-missing-season')

    inputs = described_class.new(season, ratings_config_version: version).preview_inputs(team_season)

    expect(inputs).to include(previous_season: nil, previous_team_season: nil,
                              baselines: { 'adj_offensive_efficiency' => 105.5,
                                           'adj_defensive_efficiency' => 105.5, 'adj_pace' => 69.5 })
    expect(inputs[:baseline_sources].values.uniq).to eq(
      ['configuration.preseason.fallback_efficiency', 'configuration.preseason.fallback_pace']
    )
  end

  it 'keeps the coaching source history lookup separate from the baseline history lookup' do
    season = create(:season, year: 2027)
    destination = create(:team)
    source = create(:team)
    team_season = create(:team_season, season:, team: destination)
    previous = create(:season, year: 2026, end_date: Date.new(2026, 4, 10), average_pace: 69)
    create(:team_season, season: previous, team: destination, adj_pace: 68)
    create(:team_season, season: previous, team: source, adj_pace: 74)
    CoachingChange.create!(team: destination, previous_team: source, effective_year: 2027, previous_year: 2026,
                           coach_name: 'Synthetic Coach', previous_role: 'head_coach', full_season_head_coach: true,
                           previous_season_d1: true, status: 'confirmed')
    CoachingReview.find_or_initialize_by(year: 2027).update!(ready: true)
    config = RatingsConfigVersion.authored_config.deep_dup
    config[:bundle_name] = 'explicit-prior-coaching-source-query'
    config[:preseason][:coaching] = { formula: 'relative_pace_v2', weight: 0.5 }
    version = RatingsConfigVersion.publish!(config)
    calculator = described_class.new(season, ratings_config_version: version)

    _inputs, query_count = count_prior_team_season_queries { calculator.preview_inputs(team_season) }

    expect(query_count).to eq(2)
  end
end
