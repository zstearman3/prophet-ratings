# == Schema Information
#
# Table name: seasons
#
#  id                       :bigint           not null, primary key
#  average_efficiency       :decimal(6, 3)
#  average_pace             :decimal(6, 3)
#  efficiency_std_deviation :decimal(6, 3)
#  end_date                 :date             not null
#  pace_std_deviation       :decimal(6, 3)
#  start_date               :date             not null
#  year                     :integer          not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  index_seasons_on_year  (year) UNIQUE
#
FactoryBot.define do
  factory :season do
    sequence(:year) { |n| 2020 + n }
    start_date { Date.new(year, 11, 1) }
    end_date { Date.new(year + 1, 4, 1) }
  end
end
