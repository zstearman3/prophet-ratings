# frozen_string_literal: true

# == Schema Information
#
# Table name: teams
#
#  id             :bigint           not null, primary key
#  home_venue     :string
#  location       :string
#  nickname       :string
#  primary_color  :string
#  school         :string
#  secondary_name :string
#  short_name     :string
#  slug           :string
#  url            :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_teams_on_school  (school) UNIQUE
#  index_teams_on_slug    (slug) UNIQUE
#
class Team < ApplicationRecord
  validates :school, presence: true, uniqueness: true
  validates :url, presence: true
  validates :slug, presence: true, uniqueness: true

  before_validation :set_slug, on: :create

  has_many :team_seasons, dependent: :destroy
  has_many :team_games, dependent: :destroy
  has_many :home_team_games, -> { where(home: true) }, inverse_of: :team, class_name: 'TeamGame', dependent: :destroy
  has_many :away_team_games, -> { where(home: false) }, inverse_of: :team, class_name: 'TeamGame', dependent: :destroy
  has_many :games, through: :team_games
  has_many :home_games, through: :home_team_games, source: :game
  has_many :away_games, through: :away_team_games, source: :game
  has_many :team_conferences, dependent: :destroy
  has_many :conferences, through: :team_conferences

  scope :search, lambda { |name|
    where('school = :name OR nickname = :name OR secondary_name = :name', name:)
  }

  scope :missing_secondary_name, -> { includes(:team_games).where(team_games: { id: nil }, secondary_name: nil) }

  def to_param
    slug
  end

  def conference_for(season)
    team_conferences.find do |tc|
      season.year >= tc.start_season.year &&
        (tc.end_season.nil? || season.year <= tc.end_season.year)
    end&.conference
  end

  def current_conference
    conference_for(Season.current)
  end

  private

  def set_slug
    self.slug = school.parameterize
  end

  # Not ideal but until enough data will help determine if a game is neutral
  def probable_home_venue
    arr = home_games.order(start_time: :desc).pluck(:location).first(5)
    arr.max_by { |i| arr.count(i) }
  end
end
