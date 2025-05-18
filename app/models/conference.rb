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
  def team_seasons_for_season(season = Season.current)
    TeamSeason
      .joins(:team)
      .joins('INNER JOIN team_conferences ON team_conferences.team_id = teams.id')
      .where(team_conferences: { conference_id: id })
      .where(season:)
  end
end
