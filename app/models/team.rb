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
  has_many :team_aliases, dependent: :destroy

  def self.search(name)
    joins(:team_aliases)
      .where('teams.school = :name OR teams.nickname = :name OR team_aliases.value = :name', name:)
      .first || (Rails.logger.warn("Team not found for: #{name}") && nil)
  end

  def to_param
    slug
  end

  def conference_for(season)
    return if season.blank?

    team_conferences
      .joins('INNER JOIN seasons AS lookup_start_seasons ON lookup_start_seasons.id = team_conferences.start_season_id')
      .joins('LEFT JOIN seasons AS lookup_end_seasons ON lookup_end_seasons.id = team_conferences.end_season_id')
      .where(lookup_start_seasons: { year: ..season.year })
      .where('lookup_end_seasons.id IS NULL OR lookup_end_seasons.year >= ?', season.year)
      .includes(:conference)
      .first
      &.conference
  end

  def current_conference
    conference_for(Season.current)
  end

  private

  def set_slug
    self.slug = school.parameterize
  end

  def probable_home_venue
    arr = home_games.venue_home.order(start_time: :desc).pluck(:venue_name).compact_blank.first(5)
    arr.max_by { |i| arr.count(i) }
  end
end
