# frozen_string_literal: true

# Presentation of one proposal, its live comparison and immutable source capture.
class PreseasonPublicationTeam
  def initialize(entry, row, model, mode)
    @entry = entry
    @row = row
    @model = model
    @mode = mode
  end

  def call
    entry.merge(capture_identity).merge('team_name' => row.team.school,
                                        'before' => before, 'after' => after, 'deltas' => deltas,
                                        'fallbacks' => inputs.fetch('previous_values').select do |_, value|
                                          value.blank?
                                        end.keys,
                                        'legacy_components' => legacy_components)
  end

  private

  attr_reader :entry, :row

  def capture_identity
    prior = PreseasonPrior.find_by(team_season: row, ratings_config_version: @model)
    { 'capture_id' => prior&.id, 'reuses_capture' => @mode == 'initialize' && prior.present? }
  end

  def inputs
    entry.fetch('inputs')
  end

  def before
    { 'offense' => row.adj_offensive_efficiency&.to_f, 'defense' => row.adj_defensive_efficiency&.to_f,
      'pace' => row.adj_pace&.to_f, 'net' => row.rating&.to_f, 'rank' => row.overall_rank }
  end

  def after
    outputs = entry.fetch('outputs_after')
    offense, defense, pace = outputs.values_at(*ProphetRatings::PreseasonPriorFormula::STATS.map { |stat| "preseason_#{stat}" })
    { 'offense' => offense, 'defense' => defense, 'pace' => pace, 'net' => (offense - defense).round(3) }
  end

  def deltas
    old = before
    after.to_h { |stat, value| [stat, old[stat] && (value - old.fetch(stat)).round(3)] }
  end

  def profile
    inputs.fetch('profile_values')
  end

  def legacy_components
    settings = @model.config.fetch('preseason').fetch('profile')
    recruiting, returning = profile.values_at('recruiting_score', 'returning_minutes_pct')
    { 'recruiting' => recruiting && (recruiting * settings.fetch('recruiting_score_multiplier')),
      'attrition' => returning && ((1 - returning) * settings.fetch('attrition_multiplier')),
      'manual' => profile['manual_adjustment'], 'cap' => settings.fetch('max_efficiency_adjustment') }
  end
end
