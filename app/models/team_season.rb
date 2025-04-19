# frozen_string_literal: true

# == Schema Information
#
# Table name: team_seasons
#
#  id                                  :bigint           not null, primary key
#  adj_defensive_efficiency            :decimal(6, 3)
#  adj_defensive_rebound_rate          :decimal(6, 5)
#  adj_effective_fg_percentage         :decimal(6, 5)
#  adj_effective_fg_percentage_allowed :decimal(6, 5)
#  adj_free_throw_rate                 :decimal(6, 5)
#  adj_free_throw_rate_allowed         :decimal(6, 5)
#  adj_offensive_efficiency            :decimal(6, 3)
#  adj_offensive_rebound_rate          :decimal(6, 5)
#  adj_pace                            :decimal(6, 3)
#  adj_three_pt_attempt_rate           :decimal(6, 5)
#  adj_three_pt_attempt_rate_allowed   :decimal(6, 5)
#  adj_turnover_rate                   :decimal(6, 5)
#  adj_turnover_rate_forced            :decimal(6, 5)
#  away_defense_penalty                :decimal(6, 3)
#  away_offense_penalty                :decimal(6, 3)
#  defensive_efficiency                :decimal(6, 3)
#  defensive_efficiency_std_dev        :decimal(6, 3)
#  effective_fg_percentage             :decimal(6, 5)
#  free_throw_rate                     :decimal(6, 5)
#  home_defense_boost                  :decimal(6, 3)
#  home_offense_boost                  :decimal(6, 3)
#  offensive_efficiency                :decimal(6, 3)
#  offensive_efficiency_std_dev        :decimal(6, 3)
#  offensive_rebound_rate              :decimal(6, 5)
#  pace                                :decimal(6, 3)
#  rating                              :decimal(6, 3)
#  three_pt_attempt_rate               :decimal(6, 5)
#  turnover_rate                       :decimal(6, 5)
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  season_id                           :bigint           not null
#  team_id                             :bigint           not null
#
# Indexes
#
#  index_team_seasons_on_season_id              (season_id)
#  index_team_seasons_on_team_id                (team_id)
#  index_team_seasons_on_team_id_and_season_id  (team_id,season_id) UNIQUE
#
class TeamSeason < ApplicationRecord
  belongs_to :season
  belongs_to :team

  has_many :team_games, dependent: :destroy
  has_many :games, through: :team_games
end
