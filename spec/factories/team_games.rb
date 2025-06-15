# frozen_string_literal: true

# == Schema Information
#
# Table name: team_games
#
#  id                       :bigint           not null, primary key
#  assist_rate              :decimal(6, 5)
#  assists                  :integer
#  block_rate               :decimal(6, 5)
#  blocks                   :integer
#  defensive_rating         :decimal(6, 3)
#  defensive_rebound_rate   :decimal(6, 5)
#  defensive_rebounds       :integer
#  effective_fg_percentage  :decimal(6, 5)
#  field_goals_attempted    :integer
#  field_goals_made         :integer
#  field_goals_percentage   :decimal(6, 5)
#  fouls                    :integer
#  free_throw_rate          :decimal(6, 5)
#  free_throws_attempted    :integer
#  free_throws_made         :integer
#  free_throws_percentage   :decimal(6, 5)
#  home                     :boolean          default(FALSE)
#  minutes                  :integer
#  offensive_rating         :decimal(6, 3)
#  offensive_rebound_rate   :decimal(6, 5)
#  offensive_rebounds       :integer
#  points                   :integer
#  rebound_rate             :decimal(6, 5)
#  rebounds                 :integer
#  steal_rate               :decimal(6, 5)
#  steals                   :integer
#  three_pt_attempt_rate    :decimal(6, 5)
#  three_pt_attempted       :integer
#  three_pt_made            :integer
#  three_pt_percentage      :decimal(6, 5)
#  three_pt_proficiency     :decimal(6, 5)
#  true_shooting_percentage :decimal(6, 5)
#  turnover_rate            :decimal(6, 5)
#  turnovers                :integer
#  two_pt_attempted         :integer
#  two_pt_made              :integer
#  two_pt_percentage        :decimal(6, 5)
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  game_id                  :bigint           not null
#  opponent_team_season_id  :bigint
#  team_id                  :bigint           not null
#  team_season_id           :bigint           not null
#
# Indexes
#
#  index_team_games_on_game_id                  (game_id)
#  index_team_games_on_game_id_and_home         (game_id,home) UNIQUE
#  index_team_games_on_opponent_team_season_id  (opponent_team_season_id)
#  index_team_games_on_team_id                  (team_id)
#  index_team_games_on_team_id_and_game_id      (team_id,game_id) UNIQUE
#  index_team_games_on_team_season_id           (team_season_id)
#
# Foreign Keys
#
#  fk_rails_...  (opponent_team_season_id => team_seasons.id)
#
FactoryBot.define do
  factory :team_game do
    team
    team_season
    sequence(:game) { |n| association(:game, start_time: Time.zone.now.change(hour: 12 + n, min: 0, sec: 0)) }
    home { false }
    minutes { 200 }
  end
end
