# frozen_string_literal: true

# Explicit approval applies conference changes and the existing participation contract together.
class SeasonMembershipReview
  def self.reviewed_decisions(proposal, teams)
    rows = proposal.fetch('rows')
    validate_coverage(rows, teams)
    builder = self
    rows.map { |row| builder.reviewed_decision(row, teams.fetch(row.fetch('team_id').to_s), proposal.fetch('source_url')) }
  end

  def self.validate_coverage(rows, teams)
    return if teams.keys.sort == rows.pluck('team_id').map(&:to_s).sort

    raise ArgumentError, 'Review must include every proposed school exactly once.'
  end

  def self.reviewed_decision(row, decision, source_url)
    choice = decision.fetch('choice')
    reason = decision.fetch('reason', '').strip
    validate_choice(row, choice, reason)
    { 'team_id' => row.fetch('team_id'), 'choice' => choice,
      'status' => choice == 'excluded' ? 'excluded' : 'included',
      'reason' => reason.presence || "Reviewed source membership: #{source_url}" }
  end

  def self.validate_choice(row, choice, reason)
    school = row.fetch('school')
    raise ArgumentError, "#{school}: choose a membership or explicitly exclude the school." if choice == 'unresolved'
    if reason.blank? && (choice != row.fetch('choice') || choice == 'excluded')
      raise ArgumentError, "#{school}: provide a reason/evidence for the reviewed exception."
    end
    return if %w[independent excluded].include?(choice) || (/\A[1-9]\d*\z/.match?(choice) && Conference.exists?(id: choice))

    raise ArgumentError, "#{school}: invalid membership choice."
  end

  def initialize(season)
    @season = season
  end

  def refresh
    ensure_editable
    proposal = SeasonMembershipProposal.new(season.reload).capture
    locked do
      verify_capture(proposal)
      season.update!(membership_proposal: proposal)
    end
  end

  def apply(attributes, reviewer:)
    @submission = attributes.merge('reviewed_by' => reviewer)
    locked { publish_review }
  rescue KeyError, Date::Error => error
    raise ArgumentError, "Incomplete review: #{error.message}"
  end

  def proposal_key
    SeasonMembershipProposal.digest(season.membership_proposal)
  end

  private

  attr_reader :season, :submission

  def locked(&)
    Season.with_ratings_lock do
      season.with_lock do
        ensure_editable
        yield
      end
    end
  end

  def verify_capture(proposal)
    current = SeasonMembershipProposal.new(season).fingerprint
    return if proposal.values_at('initial_fingerprint', 'fingerprint') == [current, current]

    raise ArgumentError, 'Local data changed during discovery; refresh again.'
  end

  def ensure_editable
    return unless season.current? || season.rating_outputs?

    raise ArgumentError, 'Use this review before preseason publication; existing season outputs must be preserved.'
  end

  def publish_review
    validate_proposal
    decisions = self.class.reviewed_decisions(season.membership_proposal, submission.fetch('teams'))
    SeasonMembershipAssignment.new(season).call(decisions)
    save_participation(decisions)
    season.update!(membership_proposal: {})
  end

  def validate_proposal
    proposal = current_proposal
    raise ArgumentError, 'Resolve source identities and refresh before approval.' if proposal.fetch('issues').any?
    return if proposal.fetch('fingerprint') == SeasonMembershipProposal.new(season).fingerprint

    raise ArgumentError, 'Local roster, dates or memberships changed; refresh and review again.'
  end

  def current_proposal
    proposal = season.membership_proposal
    raise ArgumentError, 'Refresh proposals before approval.' if proposal.blank?
    raise ArgumentError, 'Proposal changed; reload and review again.' unless submission.fetch('proposal_key') == proposal_key

    proposal
  end

  def save_participation(decisions)
    season.update!(start_date: Date.iso8601(submission.fetch('start_date')), end_date: Date.iso8601(submission.fetch('end_date')))
    review = SeasonParticipationReview.new(season)
    review.apply(review_document(decisions))
    review.validate
  end

  def review_document(decisions)
    evidence = submission.fetch('evidence').strip
    raise ArgumentError, 'Provide roster/date evidence before approval.' if evidence.blank?

    {
      'evidence' => evidence, 'reviewed_by' => submission.fetch('reviewed_by'), 'reviewed_at' => Time.current.iso8601,
      'dates' => { 'start_date' => season.start_date.iso8601, 'end_date' => season.end_date.iso8601, 'evidence' => evidence },
      'teams' => decisions.map { |decision| decision.slice('team_id', 'status', 'reason') }, 'unresolved_identities' => [],
      'membership_source' => season.membership_proposal, 'membership_decisions' => decisions
    }
  end
end
