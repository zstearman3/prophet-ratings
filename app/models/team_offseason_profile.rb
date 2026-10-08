# frozen_string_literal: true

# == Schema Information
#
# Table name: team_offseason_profiles
#
#  id                    :bigint           not null, primary key
#  coaching_change       :boolean
#  lost_starters         :integer
#  manual_adjustment     :float
#  recruiting_class_rank :integer
#  recruiting_score      :float
#  returning_bpm_total   :float
#  returning_minutes_pct :float
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  team_season_id        :bigint           not null
#
# Indexes
#
#  index_team_offseason_profiles_on_team_season_id  (team_season_id)
#
class TeamOffseasonProfile < ApplicationRecord
  PROFILE_CONFIG = Rails.application.config_for(:ratings).deep_symbolize_keys.fetch(:preseason).fetch(:profile)

  belongs_to :team_season

  validates :returning_minutes_pct, numericality: { in: 0.0..1.0 }, allow_nil: true
  validates :recruiting_score, numericality: { greater_than_or_equal_to: 0, less_than: Float::INFINITY }, allow_nil: true
  validates :manual_adjustment, numericality: { greater_than: -Float::INFINITY, less_than: Float::INFINITY }, allow_nil: true

  def adjustment_for(stat_key)
    case stat_key
    when :adj_off_efficiency then efficiency_adjustment
    when :adj_def_efficiency then -efficiency_adjustment
    else 0
    end
  end

  def efficiency_adjustment
    manual_component = manual_adjustment&.finite? ? manual_adjustment : 0.0
    adjustment = recruitment_component - attrition_component + manual_component
    limit = PROFILE_CONFIG.fetch(:max_efficiency_adjustment)
    adjustment.clamp(-limit, limit)
  end

  private

  def recruitment_component
    return 0.0 unless recruiting_score&.finite? && recruiting_score >= 0

    recruiting_score * PROFILE_CONFIG.fetch(:recruiting_score_multiplier)
  end

  def attrition_component
    return 0.0 unless returning_minutes_pct&.finite? && (0.0..1.0).cover?(returning_minutes_pct)

    PROFILE_CONFIG.fetch(:attrition_multiplier) * (1.0 - returning_minutes_pct)
  end
end
