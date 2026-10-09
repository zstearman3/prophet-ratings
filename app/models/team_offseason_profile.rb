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
  belongs_to :team_season

  validates :returning_minutes_pct, numericality: { in: 0.0..1.0 }, allow_nil: true
  validates :recruiting_score, numericality: { greater_than_or_equal_to: 0, less_than: Float::INFINITY }, allow_nil: true
  validates :manual_adjustment, numericality: { greater_than: -Float::INFINITY, less_than: Float::INFINITY }, allow_nil: true

  def adjustment_for(stat_key, ratings_config_version: nil)
    adjustment = efficiency_adjustment(ratings_config_version:)
    case stat_key
    when :adj_off_efficiency then adjustment
    when :adj_def_efficiency then -adjustment
    else 0
    end
  end

  def efficiency_adjustment(ratings_config_version: nil)
    profile_config = RatingsConfigVersion.resolve(ratings_config_version).settings.fetch(:preseason).fetch(:profile)
    limit = profile_config.fetch(:max_efficiency_adjustment)
    profile_adjustment(profile_config).clamp(-limit, limit)
  end

  def profile_adjustment(profile_config)
    manual_component = manual_adjustment&.finite? ? manual_adjustment : 0.0
    recruitment_component(profile_config) - attrition_component(profile_config) + manual_component
  end

  private

  def recruitment_component(profile_config)
    return 0.0 unless recruiting_score&.finite? && recruiting_score >= 0

    recruiting_score * profile_config.fetch(:recruiting_score_multiplier)
  end

  def attrition_component(profile_config)
    return 0.0 unless returning_minutes_pct&.finite? && (0.0..1.0).cover?(returning_minutes_pct)

    profile_config.fetch(:attrition_multiplier) * (1.0 - returning_minutes_pct)
  end
end
