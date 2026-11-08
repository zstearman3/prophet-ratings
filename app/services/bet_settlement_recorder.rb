# frozen_string_literal: true

# Reuse the daily grader for every retained model, including inactive models.
class BetSettlementRecorder
  def self.call(game:)
    new(game).call
  end

  def self.schedule(game_id)
    Game.current_transaction.after_commit { enqueue(game_id) }
  end

  def self.enqueue(game_id)
    return unless relevant_game?(game_id)

    unless SettleBetRecommendationsJob.perform_later([game_id])
      raise ActiveJob::EnqueueError, "Bet settlement enqueue failed for game_id=#{game_id}"
    end
  rescue StandardError => error
    log_enqueue_failure(game_id, error)
    raise
  end

  def self.log_enqueue_failure(game_id, error)
    Rails.logger.error("Bet settlement enqueue failed: game_id=#{game_id} error=#{error.class}: #{error.message}")
  end

  def self.relevant_game?(game_id)
    Game.exists?(game_id) && (BetRecommendationIssue.exists?(game_id:) || BetSettlement.exists?(game_id:))
  end

  def self.result_attributes(result)
    { status: result.status, reason: result.reason, stake: result.stake, net_units: result.net_units }
  end

  def initialize(game)
    @game = game
  end

  def call
    Game.transaction(requires_new: true) do
      @game.reload.lock!
      model_ids.flat_map { |id| record_model(RatingsConfigVersion.find(id)) }.tally
    end
  end

  private

  def model_ids
    (BetRecommendationIssue.where(game: @game).distinct.pluck(:ratings_config_version_id) +
      BetSettlement.where(game: @game).distinct.pluck(:ratings_config_version_id)).uniq
  end

  def record_model(version)
    performance = DailyPredictionPerformance.new(@game, ratings_config_version: version)
    performance.markets.map do |market, result|
      settlement = BetSettlement.find_or_initialize_by(game: @game, ratings_config_version: version, bet_type: market)
      settlement.update!(
        **self.class.result_attributes(result), prediction: performance.prediction, bet_recommendation_issue: performance.issue
      )
      settlement.status
    end
  end
end
