# frozen_string_literal: true

class TeamConferenceAssignment
  def initialize(membership)
    @membership = membership
  end

  def call
    saved = false

    TeamConference.transaction do
      raise ActiveRecord::Rollback unless close_previous_membership_for_assignment?

      saved = membership.save
      raise ActiveRecord::Rollback unless saved
    end

    saved
  rescue ActiveRecord::RecordInvalid => e
    copy_record_errors(e.record)
    false
  end

  private

  attr_reader :membership

  def close_previous_membership_for_assignment?
    return true unless membership.team && membership.start_season

    previous_membership = previous_membership_for_team
    return true unless previous_membership
    return true if previous_membership.end_season&.year&.< preceding_year

    preceding_season = Season.find_by(year: preceding_year)
    unless preceding_season
      membership.errors.add(:start_season, 'requires the preceding season to close the previous membership')
      return false
    end

    previous_membership.update!(end_season: preceding_season)
    true
  end

  def previous_membership_for_team
    TeamConference
      .joins('INNER JOIN seasons AS assignment_start_seasons ON assignment_start_seasons.id = team_conferences.start_season_id')
      .where(team_id: membership.team_id || membership.team.id)
      .where(assignment_start_seasons: { year: ...membership.start_season.year })
      .includes(:end_season)
      .order('assignment_start_seasons.year DESC')
      .first
  end

  def preceding_year
    membership.start_season.year - 1
  end

  def copy_record_errors(record)
    record.errors.full_messages.each do |message|
      membership.errors.add(:base, message)
    end
  end
end
