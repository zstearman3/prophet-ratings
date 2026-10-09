# frozen_string_literal: true

namespace :ratings_config_version do
  desc 'Publish the complete authored YAML model without activating it'
  task publish: :environment do
    version = RatingsConfigVersion.publish!
    puts "Published #{version.name} (id=#{version.id}); active=#{version.current?}"
  end

  desc 'Explicitly activate an existing complete model; requires MODEL_VERSION'
  task activate: :environment do
    version = RatingsConfigVersion.find_by!(name: ENV.fetch('MODEL_VERSION'))
    version.activate
    puts "Activated #{version.name} (id=#{version.id})"
  end

  desc 'Backfill ratings_config_version_id for predictions and bet_recommendations'
  task backfill_ids: :environment do
    Prediction.where(ratings_config_version_id: nil).find_each do |prediction|
      ratings_config_version_id = prediction.home_team_snapshot.ratings_config_version_id ||
                                  prediction.away_team_snapshot.ratings_config_version_id

      if ratings_config_version_id.nil?
        puts "Warning: Could not determine ratings_config_version_id for Prediction #{prediction.id}"
        next
      end

      prediction.update!(
        ratings_config_version_id:
      )
    end

    BetRecommendation.where(ratings_config_version_id: nil).find_each do |bet_recommendation|
      prediction = bet_recommendation.prediction
      ratings_config_version_id = prediction.home_team_snapshot.ratings_config_version_id ||
                                  prediction.away_team_snapshot.ratings_config_version_id

      if ratings_config_version_id.nil?
        puts "Warning: Could not determine ratings_config_version_id for BetRecommendation #{bet_recommendation.id}"
        next
      end

      bet_recommendation.update!(
        ratings_config_version_id:
      )
    end
    puts 'Backfilled predictions and bet_recommendations using their snapshot model version IDs'
  end
end
