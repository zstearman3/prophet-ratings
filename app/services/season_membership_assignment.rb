# frozen_string_literal: true

# Applies explicitly reviewed memberships inside the caller's rollover transaction.
class SeasonMembershipAssignment
  def self.conference_id(decision)
    choice = decision.fetch('choice')
    choice.to_i unless %w[independent excluded].include?(choice)
  end

  def initialize(season)
    @season = season
  end

  def call(decisions)
    decisions.each { |decision| apply_membership(decision) }
  end

  private

  attr_reader :season

  def apply_membership(decision)
    team = Team.find(decision.fetch('team_id'))
    memberships = active_memberships(team)
    raise ArgumentError, "#{team.school}: resolve overlapping membership ranges first." if memberships.many?

    update_membership(team, memberships.first, self.class.conference_id(decision))
  end

  def update_membership(team, existing, desired_id)
    return if existing&.conference_id == desired_id

    return update_target_membership(existing, desired_id) if existing&.start_season_id == season.id
    return assign_membership(team, desired_id) if desired_id
    return unless existing

    existing.update!(end_season: Season.find_by!(year: season.year - 1))
  end

  def assign_membership(team, conference_id)
    membership = TeamConference.new(team:, conference_id:, start_season: season)
    raise ActiveRecord::RecordInvalid, membership unless TeamConferenceAssignment.new(membership).call
  end

  def active_memberships(team)
    team.team_conferences.select { |membership| membership.covers_year?(season.year) }
  end

  def update_target_membership(existing, desired_id)
    desired_id ? existing.update!(conference_id: desired_id) : existing.destroy!
  end
end
