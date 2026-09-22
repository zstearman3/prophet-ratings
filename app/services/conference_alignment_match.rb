# frozen_string_literal: true

# Resolves one source row conservatively and retains ambiguous candidates for review.
class ConferenceAlignmentMatch
  SOURCE_PATH = %r{\A(?:https?://www\.sports-reference\.com)?/cbb/schools/([^/]+)/(?:men/)?(?:\d{4}\.html)?\z}

  def self.resolve(rows)
    local_teams = Team.all.to_a
    local_conferences = Conference.all.to_a
    matches = rows.map { |row| new(row, local_teams:, local_conferences:) }
    validate_matches(matches)
    matches
  end

  def self.validate_matches(matches)
    resolved_ids = matches.filter_map { |match| match.team&.id }
    return if resolved_ids.uniq == resolved_ids

    raise SeasonConferenceAlignment::Error, 'Duplicate source rows resolve to the same stored team; no memberships changed'
  end

  def initialize(row, local_teams:, local_conferences:)
    @row = row
    @local_teams = local_teams
    @local_conferences = local_conferences
  end

  def teams
    @teams ||= stable_teams.presence || fallback_teams
  end

  def conferences
    @conferences ||= local_conferences.select do |conference|
      conference.slug == row.fetch(:conference_slug) ||
        conference.name == row.fetch(:conference_name) ||
        conference.abbreviation == row.fetch(:conference_abbreviation)
    end
  end

  def team
    teams.first if teams.one?
  end

  def conference
    conferences.first if conferences.one?
  end

  def suggestions
    matcher = self.class
    [matcher.match_suggestion(teams, team_label), matcher.match_suggestion(conferences, conference_label)].compact
  end

  def membership(season)
    TeamConference.new(team:, conference:, start_season: season) if team && conference
  end

  def self.source_slug(team)
    team.url.to_s.match(SOURCE_PATH)&.[](1)
  end

  def self.match_suggestion(records, label)
    ids = records.map(&:id)
    return if ids.one?
    return "unmatched_#{label}; resolve the stored identity before rerunning" if ids.empty?

    "ambiguous_#{label}; candidate ids=#{ids.join(',')}; resolve before rerunning"
  end

  private

  attr_reader :row, :local_teams, :local_conferences

  def stable_teams
    slug = row.fetch(:team_slug)
    local_teams.select { |candidate| self.class.source_slug(candidate) == slug }
  end

  def fallback_teams
    name = row.fetch(:team_name)
    Team.left_joins(:team_aliases).where('teams.school = :name OR team_aliases.value = :name', name:).distinct
        .reject { |candidate| self.class.source_slug(candidate).present? }
  end

  def team_label
    "team: #{row.fetch(:team_name)} [#{row.fetch(:team_slug)}]"
  end

  def conference_label
    "conference: #{row.fetch(:conference_name)} [#{row.fetch(:conference_slug)}]"
  end
end
