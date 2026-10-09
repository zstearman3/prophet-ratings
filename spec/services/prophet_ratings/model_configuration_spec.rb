# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::ModelConfiguration do
  let(:season) { create(:season, average_efficiency: nil, average_pace: nil, efficiency_std_deviation: nil, pace_std_deviation: nil) }
  let(:first) { stored_version('first', home_boost: 3, efficiency: 100, pace: 70, volatility: 2) }
  let(:second) { stored_version('second', home_boost: 7, efficiency: 110, pace: 80, volatility: 10) }

  def stored_version(name, home_boost:, efficiency:, pace:, volatility:)
    payload = RatingsConfigVersion.authored_config
    payload[:bundle_name] = name
    payload[:home_court_advantage] = home_boost
    payload[:defaults][:season_defaults] = { average_efficiency: efficiency, average_pace: pace }
    payload[:baseline_volatility] = { efficiency_volatility: volatility, pace_volatility: 4 }
    payload[:ridge][:alpha] = home_boost
    payload[:weighting].merge!(recency_decay_days: 20, min_recency_weight: home_boost / 10.0)
    if name == 'second'
      payload[:prediction][:confidence_levels] = { high_max: 0, medium_max: 0 }
      payload[:anchor][:weight] = 0.2
      payload[:weighting].merge!(preseason_decay_days: 20, min_preseason_weight: 0.2)
      payload[:preseason].merge!(fallback_efficiency: 110, fallback_pace: 80, previous_season_weight: 0.5)
      payload[:preseason][:profile] = { recruiting_score_multiplier: 0.2, attrition_multiplier: 2, max_efficiency_adjustment: 8 }
    end
    RatingsConfigVersion.publish!(payload)
  end

  def snapshots(version)
    Array.new(2) do
      create(:team_rating_snapshot, season:, team_season: create(:team_season, season:),
                                    ratings_config_version: version, adj_pace: 70, stats: {})
    end
  end

  def predict(pair, **)
    ProphetRatings::GamePredictor.new(home_rating_snapshot: pair.first, away_rating_snapshot: pair.last,
                                      season:, venue: { type: 'home' }, **).call
  end

  it 'publishes all authored settings without selecting or activating a default' do
    version = first
    expect(version.config.keys).to include('prediction', 'defaults', 'contract_version')
    expect(RatingsConfigVersion.current).to be_nil
    expect(version.settings.fetch(:prediction)).to be_frozen
  end

  it 'selects and evaluates without activating, while activation explicitly changes future defaults' do
    first.activate
    second
    ProphetRatings::PredictionEvaluator.new(ratings_config_version: second, date_range: season.start_date..season.end_date).call
    expect(RatingsConfigVersion.resolve(second.id)).to eq(second)
    expect(RatingsConfigVersion.current).to eq(first)
    second.activate
    expect(RatingsConfigVersion.default_version).to eq(second)
  end

  it 'keeps incomplete legacy versions readable but refuses to calculate or fill missing settings from YAML' do
    legacy = create(:ratings_config_version, name: 'legacy', config: { bundle_name: 'legacy', home_court_advantage: 1 })
    expect { legacy.settings }.to raise_error(ArgumentError, /complete configuration contract/)
    ProphetRatings::PredictionEvaluator.new(ratings_config_version: legacy, date_range: season.start_date..season.end_date).call
    expect(legacy.reload.config).to eq('bundle_name' => 'legacy', 'home_court_advantage' => 1)
    expect(RatingsConfigVersion.current).to be_nil
  end

  it 'rejects missing parameters and zero decay instead of applying runtime defaults' do
    payload = first.config.deep_dup
    payload['bundle_name'] = 'invalid'
    payload['prediction'] = {}
    expect { RatingsConfigVersion.publish!(payload) }.to raise_error(ArgumentError, /prediction.confidence_levels/)
    payload = first.config.deep_dup
    payload['bundle_name'] = 'zero-decay'
    payload['weighting']['recency_decay_days'] = 0
    expect { RatingsConfigVersion.publish!(payload) }.to raise_error(ArgumentError, /must be positive/)
  end

  it 'keeps activation idempotent and accepts a previously active instance after another model is activated' do
    first.activate
    first.activate
    expect(RatingsConfigVersion.current).to eq(first)
    second.activate
    first.activate
    expect(RatingsConfigVersion.current).to eq(first)
    expect(second.reload.current).to be(false)
  end

  it 'uses stored snapshot uncertainty after live ratings switch models, preserving the existing arithmetic' do
    home, away = snapshots(first)
    home.update!(stats: { offensive_efficiency_volatility: 1, defensive_efficiency_volatility: 2 })
    away.update!(stats: { offensive_efficiency_volatility: 3, defensive_efficiency_volatility: 4 })
    [home, away].each do |snapshot|
      snapshot.team_season.update!(ratings_config_version: second, offensive_efficiency_volatility: 100,
                                   defensive_efficiency_volatility: 200)
    end
    prediction = create(:prediction, game: create(:game, season:), home_team_snapshot: home, away_team_snapshot: away,
                                     ratings_config_version: first, pace: 70)
    allow(Rails.application).to receive(:config_for).and_raise('Unexpected YAML read')
    # Snapshot variances sum to 1 + 4 + 9 + 16 = 30; the existing pace factor is 70^2 / 10000 = 0.49.
    expect(prediction.margin_std_deviation).to be_within(1e-10).of(Math.sqrt(30 * 0.49))
    expect(prediction.total_std_deviation).to be_within(1e-10).of(Math.sqrt(30) * 0.49)
    home.update!(stats: {})
    expect { prediction.margin_std_deviation }.to raise_error(ArgumentError, /snapshot volatility/)
  end

  it 'refuses unsaved changes to a published configuration' do
    first.settings
    first.config['home_court_advantage'] = 99
    expect { first.settings }.to raise_error(ArgumentError, /unchanged persisted/)
  end

  it 'uses selected home court, efficiency, pace and uncertainty defaults across consecutive versions' do
    pair_one = snapshots(first)
    pair_two = snapshots(second)
    first.activate
    allow(Rails.application).to receive(:config_for).and_raise('Unexpected YAML read')
    result_one = predict(pair_one)
    result_two = predict(pair_two)
    # First: pace 70 + 70 - 70 = 70; efficiencies 100 +/- 3; score SD = 2*2*(70^2/10000) = 1.96.
    expect(result_one.values_at(:home_expected_score, :away_expected_score, :confidence_level)).to eq([72.1, 67.9, 'High'])
    expect(result_one[:win_probability_home]).to eq(StatisticsUtils.normal_cdf(4.2 / 1.96).round(4))
    # Second: pace 70 + 70 - 80 = 60; efficiencies 90 +/- 7; combined score SD = 20*0.36 = 7.2.
    expect(result_two.values_at(:home_expected_score, :away_expected_score, :confidence_level)).to eq([58.2, 49.8, 'Low'])
    expect(result_two[:win_probability_home]).to eq(StatisticsUtils.normal_cdf(8.4 / 7.2).round(4))
    expect(predict(pair_one)).to eq(result_one)
  end

  it 'supplies the same selected settings to deterministic simulation draws' do
    home, away = snapshots(second)
    allow(ProphetRatings::Gaussian).to receive(:new) do |mean, _deviation|
      instance_double(ProphetRatings::Gaussian, rand: mean)
    end
    simulation = ProphetRatings::GameSimulator.new(home_rating_snapshot: home, away_rating_snapshot: away, season:).call
    expect(simulation.values_at(:home_score, :away_score)).to eq([58.2, 49.8])
    expect(ProphetRatings::Gaussian).to have_received(:new).with(60, Math.sqrt(32))
    expect(ProphetRatings::Gaussian).to have_received(:new).with(97, Math.sqrt(200))
  end

  it 'rejects mixed snapshot versions and mismatches with an explicit selected version' do
    home, away = snapshots(first)
    other = snapshots(second).first
    expect { predict([home, other]) }.to raise_error(ArgumentError, /selected model version/)
    expect { predict([home, away], ratings_config_version: second) }.to raise_error(ArgumentError, /selected model version/)
    prediction = build(:prediction, game: create(:game, season:), home_team_snapshot: home, away_team_snapshot: away,
                                    ratings_config_version: second)
    expect(prediction).not_to be_valid
  end

  it 'uses the selected recency decay and minimum, independently of the active version' do
    first.activate
    game = create(:game, season:, start_time: Game.schedule_time_for(season.start_date))
    team_game = build(:team_game, game:)
    weights = [first, second].map do |version|
      ProphetRatings::GameWeightingService.new(game: team_game, season:, as_of: season.start_date + 10,
                                               ratings_config_version: version).call
    end
    expect(weights).to eq([0.65, 0.85])
  end

  it 'uses the selected ridge, home court and anchor in the adjustment boundary' do
    first.activate
    teams = create_three_team_round_robin(season:, stat: :offensive_efficiency, date: season.start_date + 20)
    teams.each { |team| team.update!(ratings_config_version: second) }
    season.games.find_each { |game| game.update!(venue_type: 'home', venue_confidence: 'confirmed') }
    allow(StatisticsUtils).to receive(:solve_least_squares_with_python).and_return(Array.new(6, 0))
    calculator = ProphetRatings::AdjustedStatCalculator.new(season:, raw_stat: :offensive_efficiency,
                                                            adj_stat: :adj_offensive_efficiency,
                                                            adj_stat_allowed: :adj_defensive_efficiency,
                                                            as_of: season.start_date + 20, ratings_config_version: second)
    _rows, observations, weights, metadata = calculator.send(:build_matrix_components, teams.map(&:team_id).each_with_index.to_h, 3, 100)
    expect(metadata.pluck(:home_court)).to eq([7, -7, 7, -7, 7, -7])
    expect(observations.first).to eq(0.60 - 7 - 100)
    expect(weights.last).to eq(0.2)
    calculator.call
    expect(StatisticsUtils).to have_received(:solve_least_squares_with_python).with(anything, anything, weights: anything, ridge_alpha: 7)
  end

  it 'applies stored preseason and profile coefficients and labels priors and snapshots consistently' do
    team = create(:team_season, season:)
    create(:team_offseason_profile, team_season: team, recruiting_score: 40, returning_minutes_pct: 0.8, manual_adjustment: 1)
    first.activate
    version = second
    allow(Rails.application).to receive(:config_for).and_raise('Unexpected YAML read')
    ProphetRatings::PreseasonInitializer.new(season, ratings_config_version: version).call
    expect(team.reload.preseason_prior.ratings_config_version).to eq(second)
    expect(team.preseason_prior.outputs).to eq('preseason_adj_offensive_efficiency' => 118,
                                               'preseason_adj_defensive_efficiency' => 102, 'preseason_adj_pace' => 80)
    expect(team.ratings_config_version).to eq(second)
    expect(team.team_rating_snapshots.first.ratings_config_version).to eq(second)
    expect(team.team_offseason_profile.efficiency_adjustment(ratings_config_version: second)).to eq(8)
  end

  it 'uses the selected calendar blend and floor across different versions' do
    values = [first, second].map do |version|
      calculator = ProphetRatings::AdjustedStatCalculator.new(season:, raw_stat: :offensive_efficiency,
                                                              adj_stat: :adj_offensive_efficiency,
                                                              adj_stat_allowed: :adj_defensive_efficiency,
                                                              as_of: season.start_date + 10, ratings_config_version: version)
      calculator.send(:blend_with_preseason, 120, 100)
    end
    expect(values).to eq([115, 110])
  end

  [{}, { 'preseason_adj_offensive_efficiency' => 105.5 }].each do |outputs|
    it "rejects applied prior provenance with incomplete captured outputs #{outputs.keys}" do
      version = first
      team = create(:team_season, season:)
      ProphetRatings::PreseasonInitializer.new(season, ratings_config_version: version).call
      # Emulate malformed historical JSON without mutating the immutable prior through its model API.
      PreseasonPrior.where(id: team.reload.preseason_prior_id).update_all(outputs:) # rubocop:disable Rails/SkipsModelValidations
      expect { team.reload.validate_model_inputs(version) }.to raise_error(ArgumentError, /matching model provenance/)
      publisher = ProphetRatings::TeamRatingSnapshotService.new(season:, as_of: season.start_date, ratings_config_version: version)
      expect { publisher.call }.to raise_error(ArgumentError, /matching model provenance/)
      expect(team.team_rating_snapshots.count).to eq(1)
    end
  end

  it 'excludes another models residuals from selected volatility and home boost estimates' do
    first.activate
    selected = second
    home = create(:team_season, season:, ratings_config_version: selected)
    away = create(:team_season, season:, ratings_config_version: selected)
    pair = [home, away].map { |team| create(:team_rating_snapshot, team_season: team, ratings_config_version: first) }
    4.times do |index|
      game = create(:game, season:, start_time: Game.schedule_time_for(season.start_date + index), neutral: false)
      create(:prediction, game:, home_team_snapshot: pair.first, away_team_snapshot: pair.last, ratings_config_version: first,
                          home_offensive_efficiency_error: 20 * (index + 1))
    end
    ProphetRatings::TeamSeasonStatsAggregator.new(season:, as_of: season.start_date + 3, ratings_config_version: selected).run
    expect(home.reload.offensive_efficiency_volatility).to eq(10)
    expect(home.home_offense_boost).to eq(7)
  end

  it 'rejects unknown live provenance and another model before any rating publication writes' do
    team = create(:team_season, season:, adj_offensive_efficiency: 110, ratings_config_version: nil)
    calculator = ProphetRatings::OverallRatingsCalculator.new(season, ratings_config_version: first)
    expect { calculator.call(as_of: season.start_date) }.to raise_error(ArgumentError, /Legacy live ratings/)
    team.update!(ratings_config_version: second)
    expect { calculator.call(as_of: season.start_date) }.to raise_error(ArgumentError, /another model/)
    expect(team.reload.adj_offensive_efficiency).to eq(110)
    expect(TeamRatingSnapshot.count).to eq(0)
  end

  it 'rejects inconsistent historical prediction snapshots before residual aggregation writes' do
    selected = second
    home, away = snapshots(first)
    [home, away].each { |snapshot| snapshot.team_season.update!(ratings_config_version: selected) }
    game = create(:game, season:, start_time: Game.schedule_time_for(season.start_date))
    prediction = create(:prediction, game:, home_team_snapshot: home, away_team_snapshot: away, ratings_config_version: first)
    # Emulate an inconsistent historical row written before the output-version validation existed.
    prediction.update_columns(ratings_config_version_id: selected.id) # rubocop:disable Rails/SkipsModelValidations
    aggregator = ProphetRatings::TeamSeasonStatsAggregator.new(season:, as_of: season.start_date, ratings_config_version: selected)
    expect { aggregator.run }.to raise_error(ArgumentError, /selected model version/)
  end

  it 'ignores inconsistent prediction history from another season during selected-season aggregation' do
    selected = second
    other_season = create(:season, year: season.year - 1)
    home, away = Array.new(2) do
      team = create(:team_season, season: other_season, ratings_config_version: first)
      create(:team_rating_snapshot, team_season: team, ratings_config_version: first)
    end
    game = create(:game, season: other_season, start_time: Game.schedule_time_for(other_season.start_date))
    prediction = create(:prediction, game:, home_team_snapshot: home, away_team_snapshot: away, ratings_config_version: first)
    prediction.update_columns(ratings_config_version_id: selected.id) # rubocop:disable Rails/SkipsModelValidations
    team = create(:team_season, season:, ratings_config_version: selected)
    aggregator = ProphetRatings::TeamSeasonStatsAggregator.new(season:, as_of: season.start_date, ratings_config_version: selected)
    expect { aggregator.run }.not_to raise_error
    expect(team.reload.offensive_efficiency_volatility).to eq(10)
  end
end
