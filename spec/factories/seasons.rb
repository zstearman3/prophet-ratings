# frozen_string_literal: true

# == Schema Information
#
# Table name: seasons
#
#  id                                         :bigint           not null, primary key
#  average_efficiency                         :decimal(6, 3)
#  average_pace                               :decimal(6, 3)
#  avg_adj_defensive_efficiency               :decimal(6, 3)
#  avg_adj_defensive_rebound_rate             :decimal(6, 5)
#  avg_adj_effective_fg_percentage            :decimal(6, 5)
#  avg_adj_effective_fg_percentage_allowed    :decimal(6, 5)
#  avg_adj_free_throw_rate                    :decimal(6, 5)
#  avg_adj_free_throw_rate_allowed            :decimal(6, 5)
#  avg_adj_offensive_efficiency               :decimal(6, 3)
#  avg_adj_offensive_rebound_rate             :decimal(6, 5)
#  avg_adj_three_pt_proficiency               :decimal(6, 5)
#  avg_adj_turnover_rate                      :decimal(6, 5)
#  avg_adj_turnover_rate_forced               :decimal(6, 5)
#  current                                    :boolean          default(FALSE)
#  efficiency_std_deviation                   :decimal(6, 3)
#  end_date                                   :date             not null
#  name                                       :string
#  pace_std_deviation                         :decimal(6, 3)
#  start_date                                 :date             not null
#  stddev_adj_defensive_efficiency            :decimal(6, 3)
#  stddev_adj_defensive_rebound_rate          :decimal(6, 5)
#  stddev_adj_effective_fg_percentage         :decimal(6, 5)
#  stddev_adj_effective_fg_percentage_allowed :decimal(6, 5)
#  stddev_adj_free_throw_rate                 :decimal(6, 5)
#  stddev_adj_free_throw_rate_allowed         :decimal(6, 5)
#  stddev_adj_offensive_efficiency            :decimal(6, 3)
#  stddev_adj_offensive_rebound_rate          :decimal(6, 5)
#  stddev_adj_three_pt_proficiency            :decimal(6, 5)
#  stddev_adj_turnover_rate                   :decimal(6, 5)
#  stddev_adj_turnover_rate_forced            :decimal(6, 5)
#  year                                       :integer          not null
#  created_at                                 :datetime         not null
#  updated_at                                 :datetime         not null
#
# Indexes
#
#  index_seasons_on_current  (current) UNIQUE WHERE (current IS TRUE)
#  index_seasons_on_year     (year) UNIQUE
#
FactoryBot.define do
  factory :season do
    year { 2024 }
    start_date { Date.new(year, 11, 1) }
    end_date { Date.new(year + 1, 4, 1) }
    average_efficiency { 100.0 }
    current { false }
    efficiency_std_deviation { 1.0 }
    pace_std_deviation { 1.0 }
    average_pace { 60.0 }

    trait :current do
      current { true }
    end
  end
end
