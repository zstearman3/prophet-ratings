# frozen_string_literal: true

# Each game commits independently; a retry revisits successes without duplicating stakes.
class SettleBetRecommendationsJob < HeavyJob
  def perform(game_ids)
    counts.clear
    failures = game_ids.uniq.filter_map { |id| settle_game(id) }
    logger.info("Bet settlement summary: #{counts.inspect} failed_game_ids=#{failures.inspect}")
    raise "Bet settlement failed for game IDs: #{failures.join(', ')}" if failures.any?
  end

  private

  def counts = (@counts ||= Hash.new(0))

  def settle_game(id)
    game = Game.find_by(id:)
    game ? record_game(game) : skip_deleted
  rescue StandardError => error
    failed_game_id(id, error)
  end

  def failed_game_id(id, error)
    logger.error("Bet settlement failed: game_id=#{id} error=#{error.inspect}")
    id
  end

  def skip_deleted
    counts[:deleted] += 1
    nil
  end

  def record_game(game)
    results = BetSettlementRecorder.call(game:)
    record_counts(results)
    logger.info("Bet settlement: game_id=#{game.id} statuses=#{results.inspect}")
    nil
  end

  def record_counts(results)
    results.each { |status, count| counts[status] += count }
    counts[:processed_games] += 1
    counts[:records] += results.values.sum
    counts[:settled] += results.values_at('win', 'loss', 'push').compact.sum
  end
end
