# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::ConfigurationSchema do
  let(:payload) { RatingsConfigVersion.authored_config }

  it 'rejects typos at the root and inside nested optional settings before publication' do
    [[:home_cort_advantage], %i[weighting minimum_recency_weight], %i[learning volatility max_weight],
     %i[factors turnover_rate offence_weight], %i[prediction confidence_levels high]].each do |path|
      invalid = payload.deep_dup
      parent = path[0...-1].reduce(invalid) { |hash, key| hash.fetch(key) }
      parent[path.last] = 0.2
      expect { RatingsConfigVersion.publish!(invalid) }.to raise_error(ArgumentError, /#{path.join('\.')}/)
    end
    expect(RatingsConfigVersion.count).to eq(0)
  end

  it 'rejects incompatible confidence thresholds and home-court units' do
    payload[:prediction][:confidence_levels] = { high_max: 6, medium_max: 5 }
    expect { RatingsConfigVersion.publish!(payload) }.to raise_error(ArgumentError, /high_max/)
    payload[:prediction][:confidence_levels] = { high_max: 2, medium_max: 5 }
    payload[:home_court_adjusted_stats] = ['turnover_rate']
    expect { RatingsConfigVersion.publish!(payload) }.to raise_error(ArgumentError, /points per 100/)
  end

  it 'rejects malformed nested objects with an actionable path' do
    payload[:preseason][:coaching] = nil
    expect { RatingsConfigVersion.publish!(payload) }.to raise_error(ArgumentError, /config.preseason.coaching must be an object/)
  end

  it 'keeps existing bundles readable without requiring new settings or discarding old metadata' do
    payload.delete(:learning)
    payload[:historical_note] = 'retained'
    version = create(:ratings_config_version, config: payload, name: payload[:bundle_name])
    expect(version.settings[:historical_note]).to eq('retained')
    expect(version.settings).not_to have_key(:learning)
  end
end
