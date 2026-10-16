# frozen_string_literal: true

# Conference metadata changes never rewrite participation, dates or published outputs.
class SeasonConferenceCorrection
  def self.selected_decisions(proposal, submission)
    selected = selected_rows(submission)
    rows = proposal.fetch('rows').index_by { |row| row.fetch('team_id').to_s }
    selected.map do |id, values|
      SeasonMembershipReview.reviewed_decision(rows.fetch(id), values, proposal.fetch('source_url')).except('status')
    end
  end

  def self.selected_rows(submission)
    selected = submission.fetch('teams').select { |_id, values| values['selected'] == '1' }
    if selected.empty?
      raise ArgumentError, 'Select at least one school using its row checkbox; the scope confirmation does not select schools.'
    end

    selected
  end

  def self.membership_state(decisions)
    TeamConference.where(team_id: decisions.pluck('team_id')).order(:id).map(&:attributes)
  end

  def initialize(season)
    @season = season
  end

  def call(attributes, reviewer:)
    @submission = attributes.merge('reviewed_by' => reviewer)
    locked { publish }
  rescue KeyError => error
    raise ArgumentError, "Incomplete correction: #{error.message}"
  end

  private

  attr_reader :season, :submission

  def locked(&)
    Season.with_ratings_lock { season.with_lock(&) }
  end

  def publish
    proposal = SeasonMembershipProposal.new(season).reviewed(submission)
    decisions = self.class.selected_decisions(proposal, submission)
    validate_confirmation(decisions)
    before = apply_corrections(decisions)
    save_audit(proposal, decisions, before)
  end

  def apply_corrections(decisions)
    before = self.class.membership_state(decisions)
    decisions.each { |decision| SeasonConferenceYearAssignment.new(season, decision).call }
    before
  end

  def validate_confirmation(decisions)
    unless submission['confirm_memberships_only'] == '1' && submission.fetch('evidence', '').strip.present?
      raise ArgumentError, 'Confirm conference-only scope and provide correction evidence.'
    end
    return unless decisions.any? { |decision| decision.fetch('choice') == 'excluded' }

    raise ArgumentError, 'Use Independent / no conference for membership-only corrections; N/A changes participation only in a full review.'
  end

  def save_audit(proposal, decisions, before)
    record = {
      'reviewed_by' => submission.fetch('reviewed_by'), 'reviewed_at' => Time.current.iso8601,
      'scope' => 'conference_only', 'target_year' => season.year, 'evidence' => submission.fetch('evidence').strip,
      'source' => proposal.slice('source_url', 'source_year', 'target_year', 'captured_at', 'source_rows', 'issues'),
      'decisions' => decisions, 'memberships_before' => before, 'memberships_after' => self.class.membership_state(decisions),
      'target_year_confirmed' => submission['confirm_target_year'] == '1'
    }
    season.update!(membership_corrections: season.membership_corrections + [record], membership_proposal: {})
  end
end
