# frozen_string_literal: true

# == Schema Information
#
# Table name: team_seasons
#
#  id                                       :bigint           not null, primary key
#  adj_defensive_efficiency                 :decimal(6, 3)
#  adj_defensive_efficiency_rank            :integer
#  adj_defensive_rebound_rate               :decimal(6, 5)
#  adj_defensive_rebound_rate_rank          :integer
#  adj_effective_fg_percentage              :decimal(6, 5)
#  adj_effective_fg_percentage_allowed      :decimal(6, 5)
#  adj_effective_fg_percentage_allowed_rank :integer
#  adj_effective_fg_percentage_rank         :integer
#  adj_free_throw_rate                      :decimal(6, 5)
#  adj_free_throw_rate_allowed              :decimal(6, 5)
#  adj_free_throw_rate_allowed_rank         :integer
#  adj_free_throw_rate_rank                 :integer
#  adj_offensive_efficiency                 :decimal(6, 3)
#  adj_offensive_efficiency_rank            :integer
#  adj_offensive_rebound_rate               :decimal(6, 5)
#  adj_offensive_rebound_rate_rank          :integer
#  adj_pace                                 :decimal(6, 3)
#  adj_pace_rank                            :integer
#  adj_three_pt_proficiency                 :decimal(6, 5)
#  adj_three_pt_proficiency_allowed         :decimal(6, 5)
#  adj_three_pt_proficiency_allowed_rank    :integer
#  adj_three_pt_proficiency_rank            :integer
#  adj_turnover_rate                        :decimal(6, 5)
#  adj_turnover_rate_forced                 :decimal(6, 5)
#  adj_turnover_rate_forced_rank            :integer
#  adj_turnover_rate_rank                   :integer
#  away_defense_penalty                     :decimal(6, 3)
#  away_offense_penalty                     :decimal(6, 3)
#  conference_losses                        :integer          default(0)
#  conference_wins                          :integer          default(0)
#  defensive_efficiency                     :decimal(6, 3)
#  defensive_efficiency_std_dev             :decimal(6, 3)
#  defensive_efficiency_volatility          :decimal(6, 3)
#  effective_fg_percentage                  :decimal(6, 5)
#  free_throw_rate                          :decimal(6, 5)
#  home_defense_boost                       :decimal(6, 3)
#  home_offense_boost                       :decimal(6, 3)
#  losses                                   :integer          default(0)
#  offensive_efficiency                     :decimal(6, 3)
#  offensive_efficiency_std_dev             :decimal(6, 3)
#  offensive_efficiency_volatility          :decimal(6, 3)
#  offensive_rebound_rate                   :decimal(6, 5)
#  overall_rank                             :integer
#  pace                                     :decimal(6, 3)
#  pace_rank                                :integer
#  pace_volatility                          :decimal(6, 3)
#  preseason_adj_defensive_efficiency       :decimal(6, 3)
#  preseason_adj_offensive_efficiency       :decimal(6, 3)
#  preseason_adj_pace                       :decimal(6, 3)
#  rating                                   :decimal(6, 3)
#  three_pt_attempt_rate                    :decimal(6, 5)
#  three_pt_proficiency                     :decimal(6, 5)
#  total_home_boost                         :decimal(6, 3)
#  total_volatility                         :decimal(6, 3)
#  turnover_rate                            :decimal(6, 5)
#  wins                                     :integer          default(0)
#  created_at                               :datetime         not null
#  updated_at                               :datetime         not null
#  season_id                                :bigint           not null
#  team_id                                  :bigint           not null
#
# Indexes
#
#  index_team_seasons_on_season_id              (season_id)
#  index_team_seasons_on_team_id                (team_id)
#  index_team_seasons_on_team_id_and_season_id  (team_id,season_id) UNIQUE
#
class TeamSeason < ApplicationRecord
  belongs_to :team
  belongs_to :season
  has_many :team_games, dependent: :destroy
  has_many :games, through: :team_games
  has_many :team_rating_snapshots, dependent: :destroy
  has_many :predictions, through: :team_rating_snapshots

  scope :current, -> { where(season: Season.current) }

  def rank(as_of: nil)
    bundle_name = Rails.application.config_for(:ratings).bundle_name
    config = RatingsConfigVersion.find_by(name: bundle_name)

    snapshot_scope = TeamRatingSnapshot
                     .where(ratings_config_version: config)
                     .order(:team_season_id, snapshot_date: :desc)

    snapshot_scope = snapshot_scope.where('snapshot_date <= ?', as_of) if as_of.present?

    # DISTINCT ON requires ordering by the same column(s)
    snapshots = snapshot_scope.select('DISTINCT ON (team_season_id) *').to_a

    sorted = snapshots.sort_by { |s| [-s.rating, s.team_season_id] }

    index = sorted.find_index { |s| s.team_season_id == id }

    index ? index + 1 : nil
  end

  def conference
    team.conference_for(season)
  end
end
