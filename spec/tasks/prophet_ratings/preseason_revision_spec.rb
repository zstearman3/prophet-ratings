# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe ProphetRatings::PreseasonRevision do
  let(:season) { create(:season) }
  let(:version) { create(:ratings_config_version) }

  around do |example|
    original_rake = Rake.application
    original_env = ENV.to_h
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join('lib/tasks/season_bootstrap.rake')
    %w[YEAR MODEL_VERSION APPLY PREVIEW_KEY].each { |key| ENV.delete(key) }
    example.run
  ensure
    Rake.application = original_rake
    ENV.replace(original_env)
  end

  def invoke
    Rake::Task['season:revise_preseason'].reenable
    Rake::Task['season:revise_preseason'].invoke
  end

  it 'requires explicit model selection and refuses publication without a reviewed key' do
    ENV['YEAR'] = season.year.to_s
    expect { invoke }.to raise_error(SystemExit)
    create(:team_season, season:)
    ENV['MODEL_VERSION'] = version.name
    ENV['APPLY'] = 'true'
    expect { invoke }.to raise_error(SystemExit)
    expect([PreseasonPrior.count, TeamRatingSnapshot.count]).to eq([0, 0])
  end

  it 'prints a read-only preview then publishes the explicitly reviewed version' do
    create(:team_season, season:)
    ENV['YEAR'] = season.year.to_s
    ENV['MODEL_VERSION'] = version.name
    expect { invoke }.to output(/model_version.*#{version.name}.*preview_key/m).to_stdout
    expect([PreseasonPrior.count, RatingsConfigVersion.current]).to eq([0, nil])
    ENV['PREVIEW_KEY'] = described_class.new(season, ratings_config_version: version).preview.fetch(:preview_key)
    ENV['APPLY'] = 'true'
    expect { invoke }.to output(/#{version.name}/).to_stdout
    expect(season.reload.preseason_revision).to eq(version)
    expect(RatingsConfigVersion.current).to be_nil
  end
end
