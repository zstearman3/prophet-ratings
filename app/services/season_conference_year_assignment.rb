# frozen_string_literal: true

# Corrects a single year's membership while preserving preceding/following ranges.
class SeasonConferenceYearAssignment
  def initialize(season, decision)
    @season = season
    @team = Team.find(decision.fetch('team_id'))
    @conference_id = SeasonMembershipAssignment.conference_id(decision)
  end

  def call
    memberships = SeasonMembershipProposal.memberships_at(team, season.year)
    raise ArgumentError, "#{team.school}: resolve overlapping membership ranges first." if memberships.many?

    @membership = memberships.first
    return if membership&.conference_id == conference_id

    replace_membership
  end

  private

  attr_reader :season, :team, :conference_id, :membership

  def replace_membership
    preserve_surrounding_years if membership
    TeamConference.create!(team:, conference_id:, start_season: season, end_season: season) if conference_id
  end

  def preserve_surrounding_years
    old_end = membership.end_season
    preserve_range(following_season(old_end), old_end)
  end

  def following_season(old_end)
    year = season.year
    boundary_season(year + 1) if !old_end || old_end.year > year
  end

  def preserve_range(following, old_end)
    if membership.start_season.year < season.year
      split_prior_range(following, old_end)
    elsif following
      membership.update!(start_season: following)
    else
      membership.destroy!
    end
  end

  def split_prior_range(following, old_end)
    membership.update!(end_season: boundary_season(season.year - 1))
    TeamConference.create!(team:, conference: membership.conference, start_season: following, end_season: old_end) if following
  end

  def boundary_season(year)
    Season.find_by(year:) || raise(ArgumentError, "Prepare boundary season YEAR=#{year} before a target-year-only correction.")
  end
end
