# frozen_string_literal: true

# A complete, append-only pregame evaluation, including unavailable markets.
class BetRecommendationIssue < ApplicationRecord
  MARKETS = %w[spread moneyline total].freeze
  DISPLAY_FIELDS = %w[team vegas_line vegas_odds model_value confidence ev recommended].freeze

  belongs_to :game
  belongs_to :prediction
  belongs_to :ratings_config_version

  def readonly? = persisted?

  def self.capture(game:, prediction:, evaluation:)
    issued_at = Time.current
    return unless eligible?(game, prediction, issued_at)

    append_issue(issue_attributes(game, prediction, evaluation), issued_at)
  end

  def self.append_issue(attributes, issued_at)
    previous = where(game: attributes[:game], prediction: attributes[:prediction]).order(issued_at: :desc, id: :desc).first
    return previous if previous && attributes.all? { |key, value| previous.public_send(key) == value }

    create!(**attributes, issued_at:)
  end

  def self.issue_attributes(game, prediction, evaluation)
    odds = evaluation[:odds]
    { game:, prediction:, ratings_config_version_id: prediction.ratings_config_version_id,
      captured_start_time: game.start_time, odds_fetched_at: odds&.fetched_at,
      evidence: { contract_version: 1, game_odd_id: odds&.id, participants: participant_identities(game),
                  team_names: { home: game.home_team_name, away: game.away_team_name },
                  markets: market_evidence(evaluation.fetch(:recommendations)) }.deep_stringify_keys }
  end

  def self.market_evidence(recommendations)
    available = recommendations.compact.index_by(&:bet_type)
    MARKETS.index_with { |market| available[market]&.attributes&.slice(*DISPLAY_FIELDS) }
  end

  def self.participant_identities(game)
    [game.home_team_game, game.away_team_game].map { |side| [side&.team_id, side&.team_season_id] }
  end

  def self.eligible?(game, prediction, issued_at)
    game.scheduled? && !game.home_team_score && !game.away_team_score && verified_forecast?(game, prediction, issued_at)
  end

  def self.verified_forecast?(game, prediction, issued_at)
    return false unless prediction&.forecast_kind == 'pregame' && prediction.calculation_context['contract_version'] == 1

    generated = prediction.generated_at
    captured_start = prediction.forecast_start_time
    cutoff = prediction.input_cutoff
    generated && issued_at && captured_start && cutoff && generated <= issued_at &&
      issued_at < game.start_time && issued_at < captured_start && cutoff < game.schedule_date &&
      !prediction.participant_exclusion_reason
  end

  def exclusion_reason(current_game, forecast)
    return 'Saved participants do not match' unless evidence['participants'] == self.class.participant_identities(current_game)
    return 'Invalid saved issue identity' unless ratings_config_version_id == forecast.ratings_config_version_id &&
                                                 evidence['contract_version'] == 1
    return 'Invalid saved issue timing' unless valid_timing?(current_game, forecast)

    nil
  end

  private

  def valid_timing?(current_game, forecast)
    issued = issued_at
    fetched = odds_fetched_at
    fetched && forecast.generated_at <= issued && fetched <= issued && issued < captured_start_time &&
      issued < current_game.start_time && issued < forecast.forecast_start_time
  end
end
