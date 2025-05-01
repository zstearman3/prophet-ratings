# frozen_string_literal: true

# == Schema Information
#
# Table name: games
#
#  id              :bigint           not null, primary key
#  away_team_name  :string           not null
#  away_team_score :integer
#  home_team_name  :string           not null
#  home_team_score :integer
#  location        :string
#  minutes         :integer
#  neutral         :boolean
#  possessions     :decimal(4, 1)
#  start_time      :datetime         not null
#  status          :integer          default("scheduled"), not null
#  url             :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  season_id       :bigint           not null
#
# Indexes
#
#  index_games_on_season_id  (season_id)
#
FactoryBot.define do
  factory :game do
    sequence(:url) { |n| "https://example.com/game/#{n}" }
    start_time { Time.zone.now }
    season
    status { :final }
    home_team_name { 'Home Team' }
    away_team_name { 'Away Team' }
  end
end
