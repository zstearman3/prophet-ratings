# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RatingsConfigVersion do
  it 'rejects silently reusing a name for different assumptions and preserves existing configuration' do
    original = { bundle_name: 'frozen', preseason: { previous_season_weight: 0.85 } }
    version = described_class.find_or_create_by_config(original)
    expect(described_class.find_or_create_by_config(original.deep_stringify_keys)).to eq(version)
    expect { described_class.find_or_create_by_config(original.merge(preseason: {})) }.to raise_error(ArgumentError, /new bundle_name/)
    expect(version.update(config: { changed: true })).to be(false)
    expect(version.reload.config).to eq(original.deep_stringify_keys)
    expect(version.update(current: true)).to be(true)
  end
end
