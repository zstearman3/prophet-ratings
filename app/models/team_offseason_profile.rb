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
  INPUT_UNITS = {
    'recruiting_score' => 'local_score', 'returning_minutes_pct' => 'fraction',
    'manual_adjustment' => 'points_per_100_possessions_per_side'
  }.freeze

  belongs_to :team_season

  validates :team_season_id, uniqueness: true
  validate :validate_evidence, if: :evidence_required?

  def self.duplicate_team_season_ids
    group(:team_season_id).having('COUNT(*) > 1').count.keys.sort
  end

  def evidence_required?
    INPUT_UNITS.keys.any? { |key| self[key].present? }
  end

  def validate_evidence
    errors.add(:source_reference, 'is required for supplied inputs') if source_reference.blank?
    errors.add(:observed_on, 'is required for supplied inputs') if observed_on.blank?
    errors.add(:input_units, "must be #{INPUT_UNITS.inspect}") unless input_units == INPUT_UNITS
    errors.add(:manual_adjustment_reason, 'is required even for zero') if manual_adjustment.present? && manual_adjustment_reason.blank?
  end

  validates :returning_minutes_pct, numericality: { in: 0.0..1.0 }, allow_nil: true
  validates :recruiting_score, numericality: { greater_than_or_equal_to: 0, less_than: Float::INFINITY }, allow_nil: true
  validates :manual_adjustment, numericality: { greater_than: -Float::INFINITY, less_than: Float::INFINITY }, allow_nil: true

  def validate_revision_evidence
    return if valid?

    raise ArgumentError, "Resolve offseason profile #{id} evidence/units: #{errors.full_messages.join('; ')}"
  end

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
