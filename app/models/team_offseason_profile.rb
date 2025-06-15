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

  def adjustment_for(stat_key)
    case stat_key
    when :adj_off_efficiency then efficiency_adjustment
    when :adj_def_efficiency then -efficiency_adjustment
    else 0
    end
  end

  def efficiency_adjustment
    recruitment_component - attrition_component + (manual_adjustment || 0)
  end

  private

  def recruitment_component
    return 3.0 unless recruiting_score

    recruiting_score * 0.1
  end

  def attrition_component
    return 3.0 unless returning_minutes_pct

    5.0 * (1.0 - returning_minutes_pct)
  end
end
