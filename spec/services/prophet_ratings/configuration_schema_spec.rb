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

  it 'rejects unsupported values through the shared authoring boundary' do
    [
      [:weighting, :minimum_recency_weight, 0.2],
      [:preseason, :coaching, nil],
      [:weighting, :recency_decay_days, '60'],
      [:weighting, :recency_decay_days, 0],
      [:preseason, :previous_season_weight, 1.1]
    ].each do |section, setting, value|
      invalid = payload.deep_dup
      invalid.fetch(section)[setting] = value
      version = RatingsConfigVersion.new(name: invalid[:bundle_name], config: invalid)

      expect(version.save).to be(false)
      expect(version.errors.full_messages.join).to include(setting.to_s)
      expect(RatingsConfigVersion.exists?(name: invalid[:bundle_name])).to be(false)
    end
  end

  it 'rejects non-object root and required nested object through ordinary saves' do
    [nil, [], 'bad'].each do |root|
      version = RatingsConfigVersion.new(name: 'invalid-root', config: root)
      expect(version.save).to be(false)
      expect(version.errors.full_messages.join).to match(/config.*object/i)
    end

    invalid = payload.deep_dup
    invalid[:weighting] = 'bad'
    version = RatingsConfigVersion.new(name: invalid[:bundle_name], config: invalid)
    expect(version.save).to be(false)
    expect(version.errors.full_messages.join).to include('config.weighting')
  end

  it 'rejects unsupported prediction formula combinations before persistence' do
    invalid = payload.deep_dup
    invalid[:prediction].merge!(uncertainty_model: 'future-model', probability_precision: 'float64_v1')
    version = RatingsConfigVersion.new(name: invalid[:bundle_name], config: invalid)
    expect(version.save).to be(false)
    expect(version.errors.full_messages.join).to include('Unsupported prediction uncertainty model')

    invalid[:prediction].merge!(uncertainty_model: nil, probability_precision: 'float64_v1')
    version = RatingsConfigVersion.new(name: 'invalid-precision', config: invalid.merge(bundle_name: 'invalid-precision'))
    expect(version.save).to be(false)
    expect(version.errors.full_messages.join).to include('requires shared_pace_v1')
  end

  it 'keeps existing bundles readable without requiring new settings or discarding old metadata' do
    payload.delete(:learning)
    payload[:historical_note] = 'retained'
    version = create(:ratings_config_version, name: payload[:bundle_name])
    version.update_columns(config: payload.deep_stringify_keys) # rubocop:disable Rails/SkipsModelValidations
    expect(version.settings[:historical_note]).to eq('retained')
    expect(version.settings).not_to have_key(:learning)
  end
end
