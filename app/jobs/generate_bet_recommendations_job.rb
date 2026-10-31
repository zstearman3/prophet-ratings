# frozen_string_literal: true

class GenerateBetRecommendationsJob < HeavyJob
  def perform
    failures = Game.scheduled.joins(:game_odd).where('games.start_time > ?', Time.current).find_each.filter_map do |game|
      generate_recommendations(game)
    end
    raise "Bet recommendation generation failed for game IDs: #{failures.join(', ')}" if failures.any?
  end

  private

  def generate_recommendations(game)
    Game.transaction(requires_new: true) { BetRecommendationGenerator.call(game:) }
    nil
  rescue StandardError => error
    logger.error("Bet recommendation generation failed: game_id=#{game.id} error=#{error.class}: #{error.message}")
    game.id
  end
end
