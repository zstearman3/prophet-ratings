# frozen_string_literal: true

# Append-only prediction inputs, provenance and selection of one eligible issuance.
module FrozenForecast
  extend ActiveSupport::Concern

  FORECAST_FIELDS = %w[calculation_context forecast_kind generated_at forecast_start_time input_cutoff revision_key
                       home_team_snapshot_id away_team_snapshot_id ratings_config_version_id game_id
                       home_offensive_efficiency away_offensive_efficiency home_defensive_efficiency away_defensive_efficiency
                       home_score away_score home_win_probability pace].freeze

  included do
    validates :revision_key, uniqueness: { scope: %i[game_id ratings_config_version_id] }, allow_nil: true
    validates :forecast_kind, inclusion: { in: %w[legacy_unverified pregame reconstruction] }
    validate :frozen_forecast_is_immutable
    validate :forecast_provenance_is_complete, on: :create
    validate :forecast_context_is_replayable, on: :create

    scope :eligible_pregame, lambda {
      joins(:game).where(forecast_kind: 'pregame').where.not(revision_key: nil)
                  .where("calculation_context ->> 'contract_version' = '1'")
                  .where('generated_at < forecast_start_time AND generated_at < games.start_time')
                  .where("input_cutoff < (games.start_time AT TIME ZONE 'UTC' AT TIME ZONE 'America/New_York')::date")
    }

    # One issuance per game/model, with deterministic tie-breaking. Sources are not joined.
    scope :selected_pregame, lambda {
      where(id: eligible_pregame.select('DISTINCT ON (game_id, ratings_config_version_id) predictions.id')
                                .order(:game_id, :ratings_config_version_id, generated_at: :desc, id: :desc))
    }
    # Preserve old residual behavior only where no verified issuance exists for the game/model.
    scope :selected_with_legacy, lambda {
      selected = selected_pregame
      legacy = where(forecast_kind: 'legacy_unverified')
               .where.not('(predictions.game_id, predictions.ratings_config_version_id) IN (?)',
                          selected.select(:game_id, :ratings_config_version_id))
      selected.or(legacy)
    }
  end

  def provenance_label
    { 'legacy_unverified' => 'Unverified legacy forecast', 'pregame' => 'Saved pregame forecast',
      'reconstruction' => 'Postgame reconstruction' }.fetch(forecast_kind)
  end

  def replay
    frozen_context.predictor.call
  end

  def frozen_context
    raise ArgumentError, 'Legacy forecast has no replayable context' unless calculation_context['contract_version'] == 1

    ProphetRatings::ForecastContext.new(calculation_context)
  end

  def forecast_team_season_id(index)
    return calculation_context.dig('snapshots', index, 'source', 'team_season_id') if calculation_context.present?

    [home_team_snapshot, away_team_snapshot].fetch(index)&.team_season_id
  end

  def forecast_home_venue?
    return calculation_context.dig('venue', 'venue_type') == 'home' if calculation_context.present?

    !game.neutral?
  end

  def forecast_home_boost(stat)
    baseline = (calculation_context.dig('model_config', 'home_court_advantage') ||
                ratings_config_version.settings.fetch(:home_court_advantage)).to_f
    fallback = { home_offense_boost: baseline, home_defense_boost: -baseline }.fetch(stat)
    return calculation_context.dig('snapshots', 0, 'stats', stat.to_s) || fallback if calculation_context.present?

    home_team_snapshot&.public_send(stat) || fallback
  end

  private

  def forecast_provenance_is_complete
    return if forecast_kind == 'legacy_unverified' && calculation_context.empty?
    return if calculation_context['contract_version'] == 1 &&
              calculation_context['model_version_id'] == ratings_config_version_id &&
              [revision_key, generated_at, forecast_start_time, input_cutoff].all?(&:present?)

    errors.add(:base, 'New forecasts require complete frozen context and provenance')
  end

  def forecast_context_is_replayable
    return if forecast_kind == 'legacy_unverified' && calculation_context.empty?

    frozen_context.predictor.call
  rescue KeyError, ArgumentError, TypeError, NoMethodError => error
    errors.add(:calculation_context, "is incomplete or invalid: #{error.message}")
  end

  def frozen_forecast_is_immutable
    return unless persisted? && calculation_context_in_database.present?
    return unless changes.keys.intersect?(FORECAST_FIELDS)

    errors.add(:base, 'Saved forecast inputs and outputs are immutable; append a revision')
  end
end
