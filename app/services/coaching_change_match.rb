# frozen_string_literal: true

# Exact identities only: name similarity never establishes prior responsibility.
class CoachingChangeMatch
  def self.normalize(value)
    value.to_s.strip.gsub(/\s+/, ' ').downcase
  end

  def initialize(row, rows:)
    @row = row
    @rows = rows
  end

  def destination_teams
    resolve_school(row.fetch(:school))
  end

  def prior_schools
    incoming = self.class.normalize(row.fetch(:new_coach))
    return [] if incoming.blank?

    rows.reject { |source| source == row }.select do |source|
      CoachingChangeMatch.normalize(source.fetch(:old_coach)) == incoming
    end.pluck(:school)
  end

  def previous_teams
    prior_schools.one? ? resolve_school(prior_schools.first) : []
  end

  def facts
    { destination_school: row.fetch(:school), coach_name: row.fetch(:new_coach).presence,
      team_id: destination_teams.one? ? destination_teams.first.id : nil,
      previous_school: prior_schools.one? ? prior_schools.first : nil,
      previous_team_id: previous_teams.one? ? previous_teams.first.id : nil }
  end

  def report
    { source: row, proposal: facts, destination_team_ids: destination_teams.map(&:id),
      possible_previous_schools: prior_schools, previous_team_ids: previous_teams.map(&:id),
      review: 'Verify identities, coach spelling/interim labels, previous role/year and full-season responsibility manually' }
  end

  private

  attr_reader :row, :rows

  def resolve_school(label)
    Team.left_joins(:team_aliases)
        .where('LOWER(TRIM(teams.school)) = :name OR LOWER(TRIM(team_aliases.value)) = :name', name: self.class.normalize(label))
        .distinct.to_a
  end
end
