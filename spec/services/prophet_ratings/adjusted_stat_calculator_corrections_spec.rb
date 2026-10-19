# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::AdjustedStatCalculator do
  let(:season) { create(:season, :current) }
  let(:version) { RatingsConfigVersion.publish! }
  let(:legacy) do
    payload = RatingsConfigVersion.authored_config.except(:ratings_formula, :factors)
    payload[:bundle_name] = 'legacy-ratings-test'
    RatingsConfigVersion.publish!(payload)
  end

  def aggregator(model = version)
    ProphetRatings::TeamSeasonStatsAggregator.new(season:, ratings_config_version: model)
  end

  def calculator(stat, model = version)
    ProphetRatings::AdjustedStatCalculator.new(season:, raw_stat: stat, adj_stat: :unused,
                                               adj_stat_allowed: :unused, ratings_config_version: model)
  end

  it 'uses the same three-point composite for a game, its season, and corrected solver observations' do
    side = build(:team_game, field_goals_attempted: 60, three_pt_made: 10, three_pt_attempted: 30)
    expected = ((2 * (10.0 / 30)) + (30.0 / 60)) / 3
    expect(side.calculated_three_pt_proficiency).to be_within(0.00001).of(expected)
    expect(aggregator.send(:calculate_average_stats, [side])[:three_pt_proficiency]).to be_within(1e-12).of(expected)
    side.three_pt_proficiency = 0.5 # A previously imported value must not enter the corrected solve.
    expect(calculator(:three_pt_proficiency).send(:stat_value_for_game, side)).to be_within(0.00001).of(expected)
    expect(calculator(:three_pt_proficiency, legacy).send(:stat_value_for_game, side)).to be_within(0.00001).of(0.5)
  end

  it 'handles zero attempts without NaN and leaves standalone percentages undefined' do
    side = build(:team_game, field_goals_attempted: 60, three_pt_made: 0, three_pt_attempted: 0,
                             two_pt_attempted: 0, free_throws_attempted: 0)
    expect(side.calculated_three_pt_percentage).to be_nil
    expect(side.calculated_two_pt_percentage).to be_nil
    expect(side.calculated_free_throws_percentage).to be_nil
    expect(side.calculated_three_pt_proficiency).to eq(0)
    expect(aggregator.send(:calculate_average_stats, [side])[:three_pt_proficiency]).to eq(0)
  end

  it 'omits undefined rebound rates from averages while retaining observed zero' do
    unavailable = build(:team_game, offensive_rebounds: 0)
    opponent = build(:team_game, defensive_rebounds: 0)
    allow(unavailable).to receive(:opponent_game).and_return(opponent)
    unavailable.offensive_rebound_rate = unavailable.calculated_offensive_rebound_rate
    observed_zero = build(:team_game, offensive_rebound_rate: 0)
    observed_half = build(:team_game, offensive_rebound_rate: 0.5)

    stats = aggregator.send(:calculate_average_stats, [unavailable, observed_zero, observed_half])

    expect(unavailable.offensive_rebound_rate).to be_nil
    expect(stats[:offensive_rebound_rate]).to eq(0.25)
  end

  %i[corrected legacy].each do |formula|
    it "omits undefined shot observations from #{formula} matrix rows and retains zero-opportunity composites" do
      model = formula == :corrected ? version : legacy
      teams = create_list(:team_season, 2, season:)
      game = create(:game, season:, status: :final, start_time: season.start_date + 20.days)
      create(:team_game, game:, team_season: teams.first, team: teams.first.team, home: true,
                         field_goals_attempted: 0, three_pt_made: 0, three_pt_attempted: 0)
      zero = create(:team_game, game:, team_season: teams.last, team: teams.last.team, home: false,
                                field_goals_attempted: 10, three_pt_made: 0, three_pt_attempted: 0)
      service = described_class.new(season:, raw_stat: :three_pt_proficiency, adj_stat: :unused,
                                    adj_stat_allowed: :unused, as_of: game.schedule_date, ratings_config_version: model)
      index = teams.map(&:team_id).each_with_index.to_h

      rows, targets, _weights, metadata = service.send(:build_matrix_components, index, 2, 0.2)

      expect(rows).to eq([[0, 1, 1, 0], [1, 1, 0, 0]])
      expect(targets).to eq([-0.2, 0])
      expect(metadata.map { |row| row.slice(:team_id, :observed) }).to eq([{ team_id: zero.team_id, observed: 0 }])
    end
  end

  it 'uses regulation-normalized pace while retaining the old bundle baseline' do
    side = build(:team_game, game: build(:game, possessions: 90, minutes: 45))
    expect(aggregator.send(:calculate_average_stats, [side])[:pace]).to eq(80)
    expect(aggregator(legacy).send(:calculate_average_stats, [side])[:pace]).to eq(90)
  end

  it 'strengthens home defense for positive predicted-minus-actual residuals, preserving old arithmetic' do
    team_season = build_stubbed(:team_season)
    prediction = instance_double(Prediction, forecast_home_venue?: true,
                                             home_offensive_efficiency_error: 0.0, home_defensive_efficiency_error: 4.0)
    allow(prediction).to receive(:forecast_home_boost).with(:home_offense_boost).and_return(2.2)
    allow(prediction).to receive(:forecast_home_boost).with(:home_defense_boost).and_return(-2.2)
    [[version, -4.2], [legacy, -0.2]].each do |model, expected|
      service = aggregator(model)
      service.instance_variable_set(:@predictions_by_side, { home: { team_season.id => Array.new(8, prediction) } })
      expect(service.send(:calculate_home_advantages, team_season)[:home_defense_boost]).to eq(expected)
    end
  end

  it 'leaves blowouts unchanged by default and downweights only large efficiency margins when enabled' do
    side = build(:team_game, game: build(:game, home_team_score: 100, away_team_score: 70))
    expect(calculator(:offensive_efficiency).send(:blowout_dampening, side)).to eq(1)
    payload = RatingsConfigVersion.authored_config
    payload[:bundle_name] = 'blowout-weight-test'
    payload[:blowout].merge!(enabled: true, max_margin: 15, cap_multiplier: 1.0)
    model = RatingsConfigVersion.publish!(payload)
    service = calculator(:offensive_efficiency, model)
    expect(service.send(:blowout_dampening, side)).to eq(0.5)
    expect(calculator(:possessions, model).send(:blowout_dampening, side)).to eq(1)
    side.game.away_team_score = 85
    expect(service.send(:blowout_dampening, side)).to eq(1)
    side.game.away_team_score = 100
    expect(service.send(:blowout_dampening, side)).to eq(1)
  end

  it 'weights both game observations without scaling efficiencies, home court, or the anchor' do
    payload = RatingsConfigVersion.authored_config
    payload[:bundle_name] = 'matrix-weight-test'
    payload[:blowout].merge!(enabled: true, max_margin: 15, cap_multiplier: 1.0)
    model = RatingsConfigVersion.publish!(payload)
    teams = create_list(:team_season, 2, season:)
    game = create(:game, season:, status: :final, start_time: season.start_date + 20.days,
                         home_team_score: 100, away_team_score: 70, venue_type: 'home', venue_confidence: 'confirmed')
    teams.each_with_index do |team, index|
      create(:team_game, game:, team_season: team, team: team.team, home: index.zero?,
                         offensive_efficiency: index.zero? ? 110 : 90)
    end
    service = described_class.new(season:, raw_stat: :offensive_efficiency, adj_stat: :adj_offensive_efficiency,
                                  adj_stat_allowed: :adj_defensive_efficiency, as_of: game.schedule_date,
                                  ratings_config_version: model)
    index = teams.map(&:team_id).each_with_index.to_h
    _rows, targets, weights, = service.send(:build_matrix_components, index, 2, 100)
    expect(targets).to eq([7.8, -7.8, 0])
    expect(weights).to eq([0.5, 0.5, 0.05])
  end

  it 'rejects unknown formulas, nonboolean switches, and enabled legacy weighting' do
    [{ ratings_formula: 'unknown' }, { blowout: { enabled: 'false' } },
     { ratings_formula: nil, blowout: { enabled: true } }].each do |overrides|
      payload = RatingsConfigVersion.authored_config.deep_merge(overrides)
      expect { RatingsConfigVersion.publish!(payload) }.to raise_error(ArgumentError)
    end
  end
end
