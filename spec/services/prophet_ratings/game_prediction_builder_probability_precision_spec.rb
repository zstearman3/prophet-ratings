# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::GamePredictionBuilder do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 10, 10, 16)) { example.run } }

  let(:season) { create(:season, average_efficiency: 100, average_pace: 70) }
  let(:payload) do
    RatingsConfigVersion.authored_config.deep_dup.tap do |config|
      config[:prediction][:probability_precision] = 'float64_v1'
    end
  end
  let(:version) { RatingsConfigVersion.publish!(payload) }
  let(:game) { create(:game, season:, venue_type: 'neutral', status: :scheduled, start_time: 1.day.from_now) }

  def issue(home_mean: 140, away_mean: 100, deviation: 5)
    [home_mean, away_mean].each_with_index do |mean, index|
      team = create(:team_season, season:)
      create(:team_game, game:, team: team.team, team_season: team, home: index.zero?)
      create(:team_rating_snapshot, :with_forecast_inputs, team_season: team, ratings_config_version: version,
                                                           snapshot_date: game.schedule_date - 1, adj_pace: 70,
                                                           adj_offensive_efficiency: mean, adj_defensive_efficiency: 100,
                                                           offensive_efficiency_volatility: deviation,
                                                           defensive_efficiency_volatility: deviation, pace_volatility: 0)
    end
    ProphetRatings::GamePredictionBuilder.new(game, ratings_config_version: version).call.reload
  end

  def evaluate(prediction, home_wins:)
    game.update!(status: :final, home_team_score: home_wins ? 80 : 70, away_team_score: home_wins ? 70 : 80)
    ProphetRatings::PredictionEvaluator.new(ratings_config_version: prediction.ratings_config_version,
                                            date_range: game.schedule_date..game.schedule_date).call
  end

  [[140, 100, false, 0.9999683287581669], [100, 140, true, 0.00003167124183311998]].each do |home, away, home_wins, expected|
    it "retains the z=#{home > away ? 4 : -4} tail through issuance, reload, replay and upset evaluation", :aggregate_failures do
      prediction = issue(home_mean: home, away_mean: away)
      probability = prediction.home_win_probability
      expect(probability).to be > 0
      expect(probability).to be < 1
      expect(probability).to be_within(1e-15).of(expected)
      expect(probability).to eq(prediction.replay[:win_probability_home])
      prediction.home_team_snapshot.update!(adj_offensive_efficiency: 200, offensive_efficiency_volatility: 30)
      season.update!(average_efficiency: 130, average_pace: 90)
      allow(Rails.application).to receive(:config_for).and_raise('Unexpected YAML read')
      expect(prediction.reload.replay[:win_probability_home]).to eq(probability)
      metrics = evaluate(prediction, home_wins:)
      expect(metrics[:log_loss]).to be_within(1e-8).of(10.3601014865)
      expect(metrics[:brier_score]).to eq((probability - (home_wins ? 1 : 0))**2)
    end
  end

  [[140, 100, 1.0], [100, 140, 0.0], [100, 100, 0.5]].each do |home, away, expected|
    it "preserves deterministic probability #{expected}" do
      prediction = issue(home_mean: home, away_mean: away, deviation: 0)
      expect(prediction.home_win_probability).to eq(expected)
      expect(prediction.replay[:win_probability_home]).to eq(expected)
      expect(evaluate(prediction, home_wins: expected.zero?)[:log_loss]).to eq('Infinity') unless home == away
    end
  end

  it 'retains equal-means probability with positive variance' do
    expect(issue(home_mean: 100).home_win_probability).to eq(0.5)
  end

  [nil, -0.1, 1.1, Float::NAN, Float::INFINITY, -Float::INFINITY].each do |invalid|
    it "rejects new frozen issuance with invalid probability #{invalid.inspect}" do
      copy = issue.dup
      copy.revision_key = SecureRandom.hex
      copy.home_win_probability = invalid
      expect(copy).not_to be_valid
      expect(copy.errors[:home_win_probability]).not_to be_empty
      expect { copy.save! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(game.predictions.count).to eq(1)
    end
  end

  it 'keeps legacy shared-pace output rounded despite current authored settings' do
    payload[:prediction].delete(:probability_precision)
    prediction = issue
    expect(prediction.home_win_probability).to eq(1.0)
    expect(prediction.replay[:win_probability_home]).to eq(1.0)
    expect(evaluate(prediction, home_wins: false)[:log_loss]).to eq('Infinity')
  end

  [nil, 1.1].each do |historical|
    it "preserves legacy creation and residual updates with probability #{historical.inspect}" do
      issued = issue
      legacy = create(:prediction, game:, ratings_config_version: version,
                                   home_team_snapshot: issued.home_team_snapshot, away_team_snapshot: issued.away_team_snapshot,
                                   home_win_probability: historical)
      expect { legacy.update!(pace_error: 3) }.not_to raise_error
      expect(legacy.reload.home_win_probability).to eq(historical)
    end
  end

  it 'rejects unsupported precision selectors' do
    payload[:prediction][:probability_precision] = 'future'
    expect { version }.to raise_error(ArgumentError, /Unsupported prediction probability precision/)
  end

  it 'requires shared-pace uncertainty for float64 precision' do
    payload[:prediction].delete(:uncertainty_model)
    expect { version }.to raise_error(ArgumentError, /float64_v1 requires shared_pace_v1/)
  end
end
