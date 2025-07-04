# frozen_string_literal: true

namespace :ratings_config_version do
  desc 'Backfill ratings_config_version_id for predictions and bet_recommendations'
  task backfill_ids: :environment do
    current_rcv = RatingsConfigVersion.current
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
      ratings_config_version_id = bet_recommendation.home_team_snapshot.ratings_config_version_id ||
                                  bet_recommendation.away_team_snapshot.ratings_config_version_id

      if ratings_config_version_id.nil?
        puts "Warning: Could not determine ratings_config_version_id for BetRecommendation #{bet_recommendation.id}"
        next
      end

      bet_recommendation.update!(
        ratings_config_version_id:
      )
    end
    puts "Backfilled predictions and bet_recommendations with ratings_config_version_id=#{current_rcv.id}"
  end
end
