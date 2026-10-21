# frozen_string_literal: true

# Display names and aliases cannot establish a provider identity.
class CbbdMembershipMatch
  attr_reader :team, :conference, :suggestions

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
    @team = TeamExternalIdentity.find_by(provider: 'cbbd', external_id: row.fetch(:team_external_id))&.team
    @conference = ConferenceExternalIdentity.find_by(provider: 'cbbd', external_id: row.fetch(:conference_external_id))&.conference
    @suggestions = identity_issues
  end

  def teams
    [team].compact
  end

  def reject_duplicate
    suggestions << "Multiple source IDs map to local school #{team.school}; resolve identities manually."
    @team = nil
  end

  private

  def identity_issues
    issues = []
    unless team
      issues << "Unmatched CBBD school #{@row.fetch(:team_name)} (#{@row.fetch(:team_external_id)}); manual identity/setup required."
    end
    unless conference
      issues << "Unmatched CBBD conference #{@row.fetch(:conference_name)} (#{@row.fetch(:conference_external_id)}); map explicitly."
    end
    issues
  end
end
