# frozen_string_literal: true

# == Schema Information
#
# Table name: conferences
#
#  id           :bigint           not null, primary key
#  abbreviation :string
#  name         :string           not null
#  slug         :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_conferences_on_name  (name)
#  index_conferences_on_slug  (slug)
#
class Conference < ApplicationRecord
  has_many :team_conferences, dependent: :destroy

  def team_seasons_for_season(season = Season.current)
    return TeamSeason.none if season.blank?

    TeamSeason
      .joins(:team)
      .joins('INNER JOIN team_conferences ON team_conferences.team_id = teams.id')
      .joins('INNER JOIN seasons AS conference_start_seasons ON conference_start_seasons.id = team_conferences.start_season_id')
      .joins('LEFT JOIN seasons AS conference_end_seasons ON conference_end_seasons.id = team_conferences.end_season_id')
      .where(team_conferences: { conference_id: id })
      .where(season:)
      .where(conference_start_seasons: { year: ..season.year })
      .where('conference_end_seasons.id IS NULL OR conference_end_seasons.year >= ?', season.year)
      .distinct
  end
end
