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
#  in_conference   :boolean          default(FALSE)
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
class Game < ApplicationRecord
  validates :url, presence: true
  validates :start_time, presence: true

  validate :unique_game_per_teams_and_date

  # Prevents duplicate games for the same teams and date (ignores time part)
  def unique_game_per_teams_and_date
    return unless home_team_name.present? && away_team_name.present? && start_time.present?

    # Find other games with same teams and same date
    date = start_time.to_date
    existing = Game.where(home_team_name:, away_team_name:)
                   .where('DATE(start_time) = ?', date)
                   .where.not(id:)

    return unless existing.exists?

    errors.add(:base, "Game with these teams already exists on #{date}. If this is a double header, please ensure start_time is unique.")
  end

  belongs_to :season
  has_one :home_team_game, -> { where(home: true) }, inverse_of: :game, class_name: 'TeamGame', dependent: :destroy
  has_one :away_team_game, -> { where(home: false) }, inverse_of: :game, class_name: 'TeamGame', dependent: :destroy
  has_one :home_team, through: :home_team_game, source: :team
  has_one :away_team, through: :away_team_game, source: :team
  has_one :home_team_season, through: :home_team_game, source: :team_season
  has_one :away_team_season, through: :away_team_game, source: :team_season
  has_many :predictions, dependent: :destroy
  has_one :game_odd, dependent: :destroy
  has_many :bookmaker_odds, dependent: :destroy
  has_many :bet_recommendations, dependent: :destroy

  enum status: { scheduled: 0, final: 1, canceled: 2 }

  def generate_prediction!
    ProphetRatings::GamePredictionBuilder.new(self).call
  end

  def finalize
    ProphetRatings::GameFinalizer.new(self).call
  end

  def current_prediction
    predictions.find do |prediction|
      prediction.home_team_snapshot == home_rating_snapshot
    end
  end

  def winning_team
    home_team_score > away_team_score ? home_team : away_team
  end

  def pace
    ((possessions.to_f / minutes) * 40.0).to_f
  end

  def overtimes
    ((minutes - 40) / 5).to_i
  end

  def overtime?
    overtimes.positive?
  end

  def status_string
    if final? && overtime?
      overtimes == 1 ? 'Final OT' : "Final #{overtimes}OT"
    else
      status.upcase
    end
  end
end
