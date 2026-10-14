# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::RecruitingContributionSettings do
  let(:config) do
    RatingsConfigVersion.authored_config.deep_dup.tap do |payload|
      payload[:preseason][:recruiting] = YAML.load_file(Rails.root.join('config/examples/recruiting_r3.yml')).symbolize_keys
    end
  end

  it 'permits the approved settings in an immutable published version without changing the authored default' do
    config[:bundle_name] = 'recruiting-component-preview'
    version = RatingsConfigVersion.publish!(config)
    expect(version.settings.dig(:preseason, :recruiting)).to eq(config.dig(:preseason, :recruiting))
    expect(version.settings.dig(:preseason, :recruiting)).to be_frozen
    expect(RatingsConfigVersion.authored_config.dig(:preseason, :recruiting)).to be_nil
  end

  { weight: -0.1, attenuation_floor: 1.1, class_points_lower: -1, class_points_upper: 60,
    baseline_net_upper: 0, max_net_efficiency: -1, formula: 'future-unsupported' }.each do |key, value|
    it "rejects invalid #{key} before publishing a model" do
      config[:preseason][:recruiting][key] = value
      expect { RatingsConfigVersion.publish!(config) }.to raise_error(ArgumentError)
    end
  end

  described_class::NUMBERS.each do |key|
    it "requires finite numeric #{key}" do
      [nil, '1', Float::NAN, Float::INFINITY].each do |invalid|
        config[:preseason][:recruiting][key] = invalid
        expect { ProphetRatings::ModelConfiguration.validate_contract(config, 'invalid') }.to raise_error(ArgumentError, /setting/)
      end
    end
  end

  it 'rejects an explicitly invalid optional block' do
    config[:preseason][:recruiting] = nil
    expect { ProphetRatings::ModelConfiguration.validate_contract(config, 'invalid') }.to raise_error(ArgumentError, /formula/)
  end
end
