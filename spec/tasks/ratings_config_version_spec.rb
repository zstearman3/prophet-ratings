# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe RatingsConfigVersion do
  around do |example|
    original_rake = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join('lib/tasks/ratings_config_version.rake')
    example.run
  ensure
    Rake.application = original_rake
  end

  it 'backfills predictions and recommendations from stored snapshots without an active model' do
    version = described_class.publish!
    snapshot = create(:team_rating_snapshot, ratings_config_version: version)
    game = create(:game, season: snapshot.season)
    prediction = create(:prediction, game:, home_team_snapshot: snapshot, away_team_snapshot: snapshot, ratings_config_version: version)
    odd = create(:game_odd, game:, fetched_at: Time.current)
    recommendation = create(:bet_recommendation, game:, prediction:, game_odd: odd, ratings_config_version: version)
    # These fixtures represent legacy records missing the output model ID.
    prediction.update_columns(ratings_config_version_id: nil) # rubocop:disable Rails/SkipsModelValidations
    recommendation.update_columns(ratings_config_version_id: nil) # rubocop:disable Rails/SkipsModelValidations

    expect do
      Rake::Task['ratings_config_version:backfill_ids'].invoke
    end.to output(/using their snapshot model version IDs/).to_stdout
    expect(prediction.reload.ratings_config_version).to eq(version)
    expect(recommendation.reload.ratings_config_version).to eq(version)
    expect(described_class.current).to be_nil
  end
end
