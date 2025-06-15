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
FactoryBot.define do
  factory :team_offseason_profile
end
