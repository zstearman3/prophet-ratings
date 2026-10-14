# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::DepartureContributionSettings do
  let(:settings) { YAML.load_file(Rails.root.join('config/examples/departures_r3.yml')).symbolize_keys }

  it 'accepts finite endpoint weights and nonnegative curve magnitudes' do
    [0, 1].each do |weight|
      expect do
        described_class.validate(settings.merge(weight:, slope: 0, max_net_efficiency: 0))
      end.not_to raise_error
    end
  end

  %i[weight slope max_net_efficiency].each do |key|
    [-1, Float::NAN, Float::INFINITY, nil, '1', true].each do |value|
      it "rejects #{key}=#{value.inspect}" do
        expect { described_class.validate(settings.merge(key => value)) }.to raise_error(ArgumentError)
      end
    end
  end

  it 'rejects unknown formulas and weights above one through the complete model contract' do
    expect { described_class.validate(settings.merge(formula: 'future')) }.to raise_error(ArgumentError, /formula/)
    config = RatingsConfigVersion.authored_config.deep_dup
    config[:preseason][:departures] = settings.merge(weight: 1.01)
    expect { ProphetRatings::ModelConfiguration.validate_contract(config, config[:bundle_name]) }.to raise_error(ArgumentError, /weight/)
  end
end
