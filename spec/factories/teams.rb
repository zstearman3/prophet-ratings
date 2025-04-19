# frozen_string_literal: true

# == Schema Information
#
# Table name: teams
#
#  id             :bigint           not null, primary key
#  home_venue     :string
#  location       :string
#  nickname       :string
#  school         :string
#  secondary_name :string
#  url            :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_teams_on_school  (school) UNIQUE
#
FactoryBot.define do
  factory :team do
    sequence(:school) { |n| "Test University #{n}" }
    nickname { 'Testers' }
    url { 'test-university' }
    location { 'Testville, TS' }
  end
end
