# frozen_string_literal: true

# One source row becomes a pending proposal, never an automatic review decision.
class CoachingChangeProposal
  def initialize(year:, match:)
    @year = year
    @match = match
  end

  def call
    result = match.report.merge(created: candidate.new_record?, conflicts: reviewed_conflicts,
                                equivalent_candidate_ids: existing_candidates.map(&:id))
    persist(result)
    result.merge(candidate_id: candidate.id, status: candidate.status, conflicting_candidate_ids: conflicting_destinations)
  end

  private

  def persist(result)
    apply_pending_facts if candidate.new_record? || (candidate.discovery_school.present? && candidate.status == 'pending')
    changed_source = record_source
    candidate.save!
    invalidate_readiness if result[:conflicts].any? && changed_source
  end

  attr_reader :year, :match

  def scoped
    CoachingChange.where(effective_year: year)
  end

  def facts
    @facts ||= match.facts
  end

  def existing_candidates
    @existing_candidates ||= sourced_candidates.presence || equivalent_candidates
  end

  def sourced_candidates
    scoped.where(discovery_school: CoachingChangeMatch.normalize(facts.fetch(:destination_school))).to_a
  end

  def equivalent_candidates
    team_ids = match.destination_teams.map(&:id)
    return [] unless team_ids.one?

    scoped.where(team_id: team_ids.first).select do |record|
      CoachingChangeMatch.normalize(record.coach_name) == CoachingChangeMatch.normalize(facts.fetch(:coach_name))
    end
  end

  def candidate
    @candidate ||= existing_candidates.one? ? existing_candidates.first : CoachingChange.new(effective_year: year)
  end

  def apply_pending_facts
    history_changed = candidate.persisted? && %i[coach_name previous_team_id previous_school].any? do |field|
      candidate.public_send(field) != facts.fetch(field)
    end
    candidate.assign_attributes(facts)
    candidate.assign_attributes(previous_year: nil, previous_role: nil, full_season_head_coach: false) if history_changed
  end

  def record_source
    row = match.report.fetch(:source)
    candidate.assign_attributes(discovery_school: CoachingChangeMatch.normalize(row.fetch(:school)),
                                discovery_coach_name: row.fetch(:new_coach), discovery_former_coach: row.fetch(:old_coach),
                                discovery_present: true, discovery_team_id: facts[:team_id],
                                discovery_previous_team_id: facts[:previous_team_id])
    CoachingChange::DISCOVERY_FIELDS.any? { |field| candidate.will_save_change_to_attribute?(field) }
  end

  def reviewed_conflicts
    return {} if candidate.new_record? || candidate.status == 'pending'

    normalizer = CoachingChangeMatch
    facts.except(*equivalent_fields).select do |field, value|
      value.present? && normalizer.normalize(candidate.public_send(field)) != normalizer.normalize(value)
    end
  end

  def equivalent_fields
    fields = []
    previous_id = facts[:previous_team_id]
    fields << :destination_school if candidate.team_id == facts[:team_id]
    fields << :previous_school if previous_id.present? && candidate.previous_team_id == previous_id
    fields
  end

  def conflicting_destinations
    team_id = candidate.team_id
    return [] unless team_id

    scoped.where(team_id:).where.not(id: candidate.id).pluck(:id)
  end

  def invalidate_readiness
    CoachingReview.where(year:).find_each { |review| review.update!(ready: false) }
  end
end
