# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::ScoreMoments do
  def moments(**options)
    values = { home: 100, away: 105, pace: 70, home_sd: 10, away_sd: 12, pace_sd: 5 }.merge(options)
    described_class.new(means: values.slice(:home, :away, :pace),
                        deviations: { home: values[:home_sd], away: values[:away_sd], pace: values[:pace_sd] })
  end

  it 'includes product variance and shared covariance in exact score, margin and total moments' do
    result = moments
    expect(result.home_variance).to be_within(1e-10).of(74.25)
    expect(result.away_variance).to be_within(1e-10).of(98.4825)
    expect(result.score_covariance).to eq(26.25)
    expect(result.margin_variance).to be_within(1e-10).of(120.2325)
    expect(result.total_variance).to be_within(1e-10).of(225.2325)
  end

  it 'includes covariance when combining the two marginal score variances' do
    result = moments
    expect(result.margin_variance).to be_within(1e-10).of(result.home_variance + result.away_variance - (2 * result.score_covariance))
    expect(result.total_variance).to be_within(1e-10).of(result.home_variance + result.away_variance + (2 * result.score_covariance))
  end

  [50, 70, 100].each do |pace|
    it "scales SD once at fixed pace #{pace}" do
      result = moments(pace:, home_sd: Math.sqrt(200), away_sd: Math.sqrt(200), pace_sd: 0)
      expect(Math.sqrt(result.margin_variance)).to be_within(1e-10).of(20 * pace / 100.0)
      expect(Math.sqrt(result.home_variance)).to be_within(1e-10).of(Math.sqrt(200) * pace / 100.0)
      expect(result.total_variance).to eq(result.margin_variance)
    end
  end

  it 'uses the independently computed normal CDF of the efficiency difference' do
    # Phi(-5/sqrt(244)) from erf, independently of StatisticsUtils.
    expected = 0.5 * (1 + Math.erf(-5 / Math.sqrt(488)))
    expect(moments.home_win_probability).to be_within(1e-10).of(expected)
    expect(moments(home: 105).home_win_probability).to eq(0.5)
    expect(moments(home_sd: 20, away_sd: 24).home_win_probability).to be_between(expected, 0.5)
    expect(moments(pace: 50, pace_sd: 0).home_win_probability).to eq(moments(pace: 100, pace_sd: 30).home_win_probability)
  end

  [100, 105, 110].zip([0.0, 0.5, 1.0]).each do |home, probability|
    it "handles deterministic efficiency difference #{home - 105}" do
      expect(moments(home:, home_sd: 0, away_sd: 0).home_win_probability).to eq(probability)
    end
  end

  %i[home_sd away_sd pace_sd].product([nil, -1, Float::NAN, Float::INFINITY]).each do |key, invalid|
    it "rejects #{key}=#{invalid.inspect}" do
      expect { moments(**{ key => invalid }) }.to raise_error(ArgumentError, /volatility/)
    end
  end

  [nil, 0, -1, Float::NAN, Float::INFINITY].each do |invalid|
    it "rejects invalid expected pace #{invalid.inspect}" do
      expect { moments(pace: invalid) }.to raise_error(ArgumentError, /pace|means/)
    end
  end
end
