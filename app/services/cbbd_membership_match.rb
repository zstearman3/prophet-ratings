# frozen_string_literal: true

# Saved provider IDs win; unique exact labels propose overridable first-time matches.
class CbbdMembershipMatch
  attr_reader :suggestions

  def self.resolve(rows)
    matches = rows.map { |row| new(row) }
    reject_duplicates(matches)
    matches
  end

  def self.reject_duplicates(matches)
    duplicates = matches.filter_map(&:team).tally.select { |_team, count| count > 1 }.keys
    matches.each { |match| match.reject_duplicate if duplicates.include?(match.team) }
  end

  def initialize(row)
    @row = row
    @identities = saved_identities
    @candidates = { teams: team_candidates, conferences: conference_candidates }
    @suggestions = identity_issues
  end

  def teams = @candidates.fetch(:teams)
  def conferences = @candidates.fetch(:conferences)
  def team = (teams.first if teams.one?)
  def conference = (conferences.first if conferences.one?)

  def pending_team
    return if @identities[:team]

    { external_id: @row.fetch(:team_external_id), name: @row.fetch(:team_name), local_id: team&.id }
  end

  def pending_conference
    return if @identities[:conference]

    { external_id: @row.fetch(:conference_external_id), name: @row.fetch(:conference_name), local_id: conference&.id }
  end

  def reject_duplicate
    suggestions << "Multiple source IDs map to local school #{team.school}; resolve identities manually."
    @candidates[:teams] = []
  end

  private

  def identity_issues
    matcher = self.class
    [matcher.match_issue(teams, "school #{@row.fetch(:team_name)} (#{@row.fetch(:team_external_id)})"),
     matcher.match_issue(conferences, "conference #{@row.fetch(:conference_name)} (#{@row.fetch(:conference_external_id)})")].compact
  end

  public_class_method def self.match_issue(candidates, label)
    return if candidates.one?

    status = candidates.empty? ? 'Unmatched' : 'Ambiguous'
    "#{status} CBBD #{label}; choose a match or complete local setup."
  end

  def saved_identities
    { team: TeamExternalIdentity.find_by(provider: 'cbbd', external_id: @row.fetch(:team_external_id)),
      conference: ConferenceExternalIdentity.find_by(provider: 'cbbd', external_id: @row.fetch(:conference_external_id)) }
  end

  def team_candidates
    identity = @identities[:team]
    return [identity.team] if identity

    Team.matching_school_or_alias(@row.fetch(:team_name)).to_a
  end

  def conference_candidates
    identity = @identities[:conference]
    return [identity.conference] if identity

    exact_conferences
  end

  def exact_conferences
    name = @row.fetch(:conference_name).strip.downcase
    abbreviation = @row.fetch(:conference_abbreviation, '').to_s.strip.downcase
    names = Conference.where('LOWER(TRIM(name)) = ?', name)
    return names.to_a if abbreviation.blank?

    names.or(Conference.where('LOWER(TRIM(abbreviation)) = ?', abbreviation)).to_a
  end
end
