# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::GamePredictor do
  let(:season) { create(:season, average_efficiency: 100, average_pace: 70) }
  let(:version) { create(:ratings_config_version) }
  let(:home) do
    create(:team_rating_snapshot, season:, team_season: create(:team_season, season:), ratings_config_version: version,
                                  adj_offensive_efficiency: 100, adj_defensive_efficiency: 100, adj_pace: 70,
                                  offensive_efficiency_volatility: 6, defensive_efficiency_volatility: 0, pace_volatility: 3)
  end
  let(:away) do
    create(:team_rating_snapshot, season:, team_season: create(:team_season, season:), ratings_config_version: version,
                                  adj_offensive_efficiency: 105, adj_defensive_efficiency: 100, adj_pace: 70,
                                  offensive_efficiency_volatility: 12, defensive_efficiency_volatility: 8, pace_volatility: 4)
  end

  def predictor(**)
    ProphetRatings::GamePredictor.new(home_rating_snapshot: home, away_rating_snapshot: away, season:,
                                      venue: { type: 'neutral' }, **).call
  end

  it 'shares unrounded combined deviations and means with persisted diagnostics' do
    result = predictor
    expect(result.values_at(:home_expected_score, :away_expected_score)).to eq([70, 73.5])
    expect(result[:meta][:margin_std_deviation]).to be_within(1e-10).of(Math.sqrt(120.2325))
    expect(result[:meta][:total_std_deviation]).to be_within(1e-10).of(Math.sqrt(225.2325))
    expect(result[:meta][:home_score_std_deviation]).to be_within(1e-10).of(Math.sqrt(74.25))
    expect(result[:meta][:away_score_std_deviation]).to be_within(1e-10).of(Math.sqrt(98.4825))
  end

  it 'uses efficiency difference for win probability' do
    result = predictor
    expect(result[:win_probability_home]).to eq((0.5 * (1 + Math.erf(-5 / Math.sqrt(488)))).round(4))
  end

  it 'shares combined deviations and means with persisted diagnostics' do
    result = predictor
    prediction = build(:prediction, game: create(:game, season:), home_team_snapshot: home, away_team_snapshot: away,
                                    ratings_config_version: version, home_offensive_efficiency: 100,
                                    away_offensive_efficiency: 105, pace: 70)
    expect(prediction.margin_std_deviation).to eq(result[:meta][:margin_std_deviation])
    expect(prediction.total_std_deviation).to eq(result[:meta][:total_std_deviation])
  end

  [70, 75].each do |sampled_pace|
    it "uses exactly one pace draw #{sampled_pace} for both scores and only two efficiency draws" do
      draws = []
      allow(ProphetRatings::Gaussian).to receive(:new) do |mean, deviation|
        draws << [mean, deviation]
        instance_double(ProphetRatings::Gaussian, rand: draws.size == 1 ? sampled_pace : mean)
      end
      result = ProphetRatings::GameSimulator.new(home_rating_snapshot: home, away_rating_snapshot: away, season:, neutral: true).call
      expect(draws).to eq([[70, 5], [100, 10], [105, 12]])
      expect(result.values_at(:home_score, :away_score)).to eq([sampled_pace, sampled_pace * 1.05])
    end
  end

  it 'applies the upset modifier to both combined efficiency deviations, without modifying pace' do
    result = predictor(upset_modifier: 2)
    expected = ProphetRatings::ScoreMoments.new(means: { home: 100, away: 105, pace: 70 }, deviations: { home: 20, away: 24, pace: 5 })
    expect(result[:meta][:margin_std_deviation]).to eq(Math.sqrt(expected.margin_variance))
    expect(result[:win_probability_home]).to eq(expected.home_win_probability.round(4))
  end

  it 'rejects missing core inputs explicitly' do
    home.adj_pace = nil
    expect { predictor }.to raise_error(ArgumentError, /finite efficiency and pace/)
  end

  it 'rejects negative snapshot deviations rather than squaring them' do
    home.pace_volatility = -1
    expect { predictor }.to raise_error(ArgumentError, /volatility/)
  end

  it 'keeps documented missing-volatility fallbacks and labels any magnitude uncalibrated' do
    home.stats = {}
    expect(predictor[:confidence_level]).to eq('Uncalibrated')
    home.offensive_efficiency_volatility = 100
    expect(predictor[:confidence_level]).to eq('Uncalibrated')
  end

  it 'keeps win probability invariant to pace changes at the predictor boundary' do
    initial = predictor
    home.adj_pace = 50
    home.pace_volatility = 30
    result = predictor
    expect(result[:win_probability_home]).to eq(initial[:win_probability_home])
    expect(result[:meta][:margin_std_deviation]).not_to eq(initial[:meta][:margin_std_deviation])
  end

  [50, 70, 100].each do |pace|
    it "returns the corrected fixed-pace margin SD at pace #{pace}" do
      [home, away].each do |snapshot|
        snapshot.adj_pace = pace
        snapshot.offensive_efficiency_volatility = 10
        snapshot.defensive_efficiency_volatility = 10
        snapshot.pace_volatility = 0
      end
      season.average_pace = pace
      expect(predictor[:meta][:margin_std_deviation]).to eq(20 * pace / 100.0)
    end
  end

  it 'publishes a selected numerical version without rewriting legacy output or reading YAML' do
    payload = version.config.deep_dup
    payload['bundle_name'] = 'legacy-uncertainty'
    payload['prediction'].delete('uncertainty_model')
    legacy = RatingsConfigVersion.publish!(payload)
    home.ratings_config_version = legacy
    away.ratings_config_version = legacy
    allow(Rails.application).to receive(:config_for).and_raise('Unexpected YAML read')
    result = predictor
    expect(result[:win_probability_home]).to eq((0.5 * (1 + Math.erf(-3.5 / (Math.sqrt(244) * 0.49 * Math.sqrt(2))))).round(4))
    expect(legacy.reload.config['prediction']).not_to have_key('uncertainty_model')
    expect(version.reload.config.dig('prediction', 'uncertainty_model')).to eq('shared_pace_v1')
  end

  it 'rejects missing stored uncertainty instead of fabricating deterministic diagnostics' do
    prediction = build(:prediction, game: create(:game, season:), home_team_snapshot: home, away_team_snapshot: away,
                                    ratings_config_version: version, home_offensive_efficiency: 100,
                                    away_offensive_efficiency: 105, pace: 70)
    home.pace_volatility = nil
    expect { prediction.margin_std_deviation }.to raise_error(ArgumentError, /volatility/)
  end
end
