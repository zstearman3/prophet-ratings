# frozen_string_literal: true

# Applies offseason decisions from the target year, preserving past and explicit future boundaries.
class SeasonMembershipAssignment
  def self.conference_id(decision)
    choice = decision.fetch('choice')
    choice.to_i unless %w[independent excluded].include?(choice)
  end

  def self.update_target_membership(existing, desired_id)
    desired_id ? existing.update!(conference_id: desired_id) : existing.destroy!
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

    return self.class.update_target_membership(existing, desired_id) if existing&.start_season_id == season.id
    return assign_membership(team, desired_id, existing) if desired_id
    return unless existing

    existing.update!(end_season: Season.find_by!(year: season.year - 1))
  end

  def assign_membership(team, conference_id, existing)
    end_season = existing ? existing.end_season : future_boundary(team)
    membership = TeamConference.new(team:, conference_id:, start_season: season, end_season:)
    raise ActiveRecord::RecordInvalid, membership unless TeamConferenceAssignment.new(membership).call
  end

  def future_boundary(team)
    next_year = team.team_conferences.joins(:start_season).where(seasons: { year: (season.year + 1).. }).minimum('seasons.year')
    return unless next_year

    year = next_year - 1
    Season.find_by(year:) || raise(ArgumentError, "Prepare boundary season YEAR=#{year} before the stored future conference change.")
  end

  def active_memberships(team)
    team.team_conferences.select { |membership| membership.covers_year?(season.year) }
  end
end
