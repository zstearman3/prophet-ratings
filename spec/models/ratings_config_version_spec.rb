# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RatingsConfigVersion do
  it 'rejects silently reusing a name for different assumptions and preserves existing configuration' do
    original = { bundle_name: 'frozen', preseason: { previous_season_weight: 0.85 } }
    version = create(:ratings_config_version, name: 'frozen')
    version.update_columns(config: original.deep_stringify_keys) # rubocop:disable Rails/SkipsModelValidations
    expect(described_class.find_or_create_by_config(original.deep_stringify_keys)).to eq(version)
    expect { described_class.find_or_create_by_config(original.merge(preseason: {})) }.to raise_error(ArgumentError, /new bundle_name/)
    expect(version.update(config: { changed: true })).to be(false)
    expect(version.reload.config).to eq(original.deep_stringify_keys)
    expect(version.update(current: true)).to be(true)
  end

  it 'rejects malformed configurations through ordinary new-record persistence' do
    payload = described_class.authored_config.merge(home_cort_advantage: 20)
    version = described_class.new(name: payload[:bundle_name], config: payload)

    expect(version.save).to be(false)
    expect(version.errors.full_messages.join).to include('home_cort_advantage')
    expect(described_class.exists?(name: payload[:bundle_name])).to be(false)
  end

  it 'rejects malformed authored payloads through publication and new factory creation' do
    payload = described_class.authored_config.merge(home_cort_advantage: 20)
    payload[:bundle_name] = 'factory-typo'
    active = create(:ratings_config_version, current: true)
    expect { described_class.publish!(payload) }.to raise_error(ArgumentError, /home_cort_advantage/)
    expect do
      described_class.find_or_create_by_config(payload)
    end.to raise_error(ActiveRecord::RecordInvalid, /home_cort_advantage/)
    expect(described_class.exists?(name: 'factory-typo')).to be(false)
    expect(described_class.current).to eq(active)
  end

  it 'preserves legacy rows and returns identical factory lookups before new-payload validation' do
    payload = described_class.authored_config
    payload[:learning].delete(:volatility)
    payload[:historical_note] = 'kept'
    row = described_class.create!(name: payload[:bundle_name], config: described_class.authored_config)
    row.update_columns(config: payload.deep_stringify_keys) # rubocop:disable Rails/SkipsModelValidations

    expect { described_class.find_or_create_by_config(payload) }.not_to change(described_class, :count)
    expect(described_class.find_or_create_by_config(payload)).to eq(row)
    expect(row.reload.config).to include('historical_note' => 'kept')
    expect(row.current).to be(false)
  end

  it 'rejects malformed root shapes with a clear validation error' do
    [nil, [], 'bad'].each do |config|
      version = described_class.new(name: 'bad-root', config:)
      expect(version.save).to be(false)
      expect(version.errors.full_messages.join).to match(/config.*object/i)
    end
  end

  it 'requires a bundle_name for new configurations' do
    payload = described_class.authored_config.except(:bundle_name)
    version = described_class.new(name: 'missing-bundle-name', config: payload)

    expect(version.save).to be(false)
    expect(version.errors.full_messages.join).to include('bundle_name')
    expect { described_class.publish!(payload) }.to raise_error(ArgumentError, /bundle_name/)
  end
end
