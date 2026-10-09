# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PinnedModelVersion do
  # Rankings dispatch now waits for real enclosing commits before enqueueing predictions.
  self.use_transactional_tests = false

  let(:season) { create(:season, :current) }
  let(:original) { RatingsConfigVersion.publish! }
  let(:replacement) { RatingsConfigVersion.publish!(RatingsConfigVersion.authored_config.merge(bundle_name: 'replacement')) }

  around do |example|
    adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = adapter
  end

  before { original.activate }

  after do
    Season.destroy_all
    Team.destroy_all
    RatingsConfigVersion.destroy_all
  end

  [UpdateRankingsJob, GenerateNightlyPredictionsJob, ResumeSeasonRatingsJob, GenerateSeasonRatingsJob].each do |job_class|
    it "serializes the selected model ID for #{job_class} before the active version changes" do
      job = job_class.perform_later(season.id)
      replacement.activate
      restored = ActiveJob::Base.deserialize(job.serialize)
      restored.send(:deserialize_arguments_if_needed)
      expect(restored.arguments.last.fetch(:ratings_config_version_id)).to eq(original.id)
      expect(restored.serialize['arguments'].last['ratings_config_version_id']).to eq(original.id)
    end
  end

  it 'builds queued nightly predictions with the originally selected snapshots after activation and YAML change' do
    game = create(:game, season:, status: :scheduled, start_time: 1.hour.from_now)
    [true, false].each do |home|
      team = create(:team_season, season:, ratings_config_version: original)
      create(:team_game, game:, team_season: team, team: team.team, home:)
      create(:team_rating_snapshot, team_season: team, ratings_config_version: original, snapshot_date: game.schedule_date - 1)
    end
    job = GenerateNightlyPredictionsJob.perform_later(season.id, as_of: Time.current)
    replacement.activate
    allow(Rails.application).to receive(:config_for).and_raise('Unexpected YAML read')
    ActiveJob::Base.deserialize(job.serialize).perform_now
    expect(game.predictions.sole.ratings_config_version).to eq(original)
    expect(game.predictions.sole.home_team_snapshot.ratings_config_version).to eq(original)
  end

  it 'executes and retries the original rankings model and pins the downstream prediction job after YAML changes' do
    calculator = instance_double(ProphetRatings::OverallRatingsCalculator, call: true)
    allow(ProphetRatings::OverallRatingsCalculator).to receive(:new).with(season, ratings_config_version: original).and_return(calculator)
    allow(GenerateNightlyPredictionsJob).to receive(:perform_later)
    job = UpdateRankingsJob.perform_later(season.id)
    replacement.activate
    restored = ActiveJob::Base.deserialize(job.serialize)
    allow(Rails.application).to receive(:config_for).and_raise('Unexpected YAML read')
    restored.perform_now
    expect(calculator).to have_received(:call)
    expect(GenerateNightlyPredictionsJob).to have_received(:perform_later).with(season.id, ratings_config_version_id: original.id)
    allow(calculator).to receive(:call).and_raise('retry me')
    restored.perform_now
    expect(restored.arguments.last.fetch(:ratings_config_version_id)).to eq(original.id)
    expect(restored.executions).to eq(2)
  end
end
