# frozen_string_literal: true

# == Schema Information
#
# Table name: team_conferences
#
#  id              :bigint           not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  conference_id   :bigint           not null
#  end_season_id   :bigint
#  start_season_id :bigint           not null
#  team_id         :bigint           not null
#
# Indexes
#
#  index_team_conferences_on_conference_id          (conference_id)
#  index_team_conferences_on_end_season_id          (end_season_id)
#  index_team_conferences_on_start_season_id        (start_season_id)
#  index_team_conferences_on_team_and_season_range  (team_id,start_season_id,end_season_id) UNIQUE
#  index_team_conferences_on_team_id                (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (conference_id => conferences.id)
#  fk_rails_...  (end_season_id => seasons.id)
#  fk_rails_...  (start_season_id => seasons.id)
#  fk_rails_...  (team_id => teams.id)
#
class TeamConference < ApplicationRecord
  belongs_to :team
  belongs_to :conference

  belongs_to :start_season, class_name: 'Season'
  belongs_to :end_season, class_name: 'Season', optional: true

  validates :start_season_id, uniqueness: { scope: :team_id }

  validate :end_season_not_before_start
  validate :membership_range_does_not_overlap

  def admin_label
    "#{team.school} — #{conference.name} (#{season_range_label})"
  end

  private

  def end_season_not_before_start
    return unless start_season && end_season
    return if end_season.year >= start_season.year

    errors.add(:end_season, 'must be the same as or later than the start season')
  end

  def membership_range_does_not_overlap
    return unless team_id && start_season

    scope = self.class
                .where(team_id:)
                .where.not(id:)
                .joins('INNER JOIN seasons AS tc_start_seasons ON tc_start_seasons.id = team_conferences.start_season_id')
                .joins('LEFT JOIN seasons AS tc_end_seasons ON tc_end_seasons.id = team_conferences.end_season_id')
                .where('tc_end_seasons.id IS NULL OR tc_end_seasons.year >= ?', start_season.year)

    scope = scope.where(tc_start_seasons: { year: ..end_season.year }) if end_season

    errors.add(:base, 'Conference membership overlaps an existing range') if scope.exists?
  end

  def season_range_label
    return "#{start_season.year}-present" unless end_season

    "#{start_season.year}-#{end_season.year}"
  end
end
