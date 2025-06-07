# frozen_string_literal: true

# == Schema Information
#
# Table name: teams
#
#  id                   :bigint           not null, primary key
#  home_venue           :string
#  location             :string
#  nickname             :string
#  primary_color        :string
#  school               :string
#  short_name           :string
#  slug                 :string
#  url                  :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  the_odds_api_team_id :string
#
# Indexes
#
#  index_teams_on_school                (school) UNIQUE
#  index_teams_on_slug                  (slug) UNIQUE
#  index_teams_on_the_odds_api_team_id  (the_odds_api_team_id) UNIQUE
#
FactoryBot.define do
  factory :team do
    school { Faker::University.name }
    slug { school.parameterize }
    nickname { 'Testers' }
    url { 'test-university' }
    location { 'Testville, TS' }
  end
end
