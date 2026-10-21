# frozen_string_literal: true

# Read-only progress summaries for the fixed offseason runbook.
class OffseasonSetupProgress
  # Status and evidence presented for one fixed workflow step.
  Step = Data.define(:key, :label, :status, :last_result, :next_action)

  def initialize(season)
    @season = season
  end

  def steps
    [prepare, memberships, recruiting, coaching, departures, preseason, schedule, activation]
  end

  private

  attr_reader :season

  def prepare
    OffseasonSetupProgress::Preparation.new(season).call
  end

  def memberships
    OffseasonSetupProgress::Memberships.new(season).call
  end

  def recruiting
    OffseasonSetupProgress::Recruiting.new(season).call
  end

  def coaching
    OffseasonSetupProgress::Coaching.new(season).call
  end

  def departures
    revision = OffseasonInputRevision.where(season:, kind: 'departures').order(:id).last
    result = revision ? "Departure revision ##{revision.id} is retained." : 'No reviewed departure revision is stored.'
    Step.new(key: 'departures', label: 'Review departures and select model', status: 'manual', last_result: result,
             next_action: 'Departure review and model selection remain existing manual work; this dashboard does not certify them.')
  end

  def preseason
    rows = season.team_seasons
    initialized = rows.where.not(adj_offensive_efficiency: nil).where.not(adj_defensive_efficiency: nil).where.not(adj_pace: nil).count
    revision = season.preseason_revision&.name || 'none selected'
    result = "#{initialized} of #{rows.count} team seasons have stored adjusted ratings; preseason revision: #{revision}."
    Step.new(key: 'preseason', label: 'Initialize and review preseason ratings', status: 'manual', last_result: result,
             next_action: 'Preseason initialization remains in the runbook; this dashboard does not certify outputs.')
  end

  def schedule
    result = "#{season.games.count} games currently stored."
    Step.new(key: 'schedule', label: 'Load and review schedule', status: 'manual', last_result: result,
             next_action: 'Schedule import and reconciliation remain a manual runbook step.')
  end

  def activation
    current = season.current? ? 'yes' : 'no'
    Step.new(key: 'activation', label: 'Review readiness and activate season', status: 'manual',
             last_result: "Current season: #{current}.",
             next_action: 'Readiness review and activation remain separate operations; this dashboard does not activate seasons.')
  end

  # Summarizes season setup without writing missing records.
  class Preparation
    def initialize(season)
      @season = season
    end

    def call
      count, missing = counts
      status = missing.zero? && count.positive? ? 'complete' : 'needs_review'
      Step.new(key: 'prepare', label: 'Prepare target season', status:,
               last_result: "#{count} team seasons stored; #{missing} teams missing.",
               next_action: 'Use the preparation form above to add missing team seasons or review dates.')
    end

    private

    attr_reader :season

    def counts
      season_id = season.id
      [TeamSeason.where(season_id:).count,
       Team.where.not(id: TeamSeason.select(:team_id).where(season_id:)).count]
    end
  end

  # Membership completion requires valid stored participation and current choices.
  class Memberships
    # Keeps reviewed approval and a newer proposal in separate evidence slots.
    Evidence = Data.define(:review, :proposal)

    def initialize(season)
      @season = season
    end

    def call
      @evidence = Evidence.new(season.participation_review, season.membership_proposal)
      build_step(currentness)
    rescue ArgumentError, KeyError, ActiveRecord::RecordNotFound => error
      Step.new(key: 'memberships', label: 'Review memberships, participation and dates', status: 'needs_review',
               last_result: error.message, next_action: 'Resolve the reported roster, alias or date issue in membership review.')
    end

    private

    attr_reader :season, :evidence

    def build_step(issues)
      status = evidence.review.present? && issues.blank? && evidence.proposal.blank? ? 'complete' : 'needs_review'
      Step.new(key: 'memberships', label: 'Review memberships, participation and dates', status:,
               last_result: result_for(issues),
               next_action: 'Review the current target-year roster, conference choices, required aliases and dates.')
    end

    def currentness
      return 'No reviewed roster is stored.' if evidence.review.blank?

      validate_participation
      decision_status
    rescue ArgumentError, ActiveRecord::RecordNotFound => error
      error.message
    end

    def validate_participation
      SeasonParticipationReview.new(season).validate
    end

    def decision_status
      decisions = evidence.review['membership_decisions']
      return 'Legacy roster approval has no retained membership decisions; current memberships need review.' if decisions.blank?
      return 'Membership decisions no longer match current target-year memberships.' unless decisions_current?(decisions)

      nil
    end

    def decisions_current?(decisions)
      decisions.all? { |decision| MembershipDecisionCurrent.new(season, decision).call }
    end

    def result_for(issues)
      [roster_result, proposal_summary, corrections_result, issues].compact_blank.join(' ')
    end

    def roster_result
      reviewed_by, reviewed_at = evidence.review&.values_at('reviewed_by', 'reviewed_at')
      return 'No participation approval is stored.' if reviewed_by.blank?

      "Roster review by #{reviewed_by} at #{reviewed_at}."
    end

    def proposal_summary
      provider, captured_at, source_year, target_year = evidence.proposal&.values_at(
        'provider', 'captured_at', 'source_year', 'target_year'
      )
      return if provider.blank?

      freshness = proposal_stale? ? 'stale' : 'unreviewed'
      "Latest proposal: #{provider} captured #{captured_at} " \
        "(#{source_year} → #{target_year})#{retained_source}. Latest proposal is #{freshness}; " \
        'the retained approval remains separate.'
    end

    def retained_source
      provider, captured_at = evidence.review&.dig('membership_source')&.values_at('provider', 'captured_at')
      "; retained approval source: #{provider} captured #{captured_at}" if provider.present?
    end

    def corrections_result
      count = season.membership_corrections.size
      "Membership corrections recorded: #{count}." if count.positive?
    end

    def proposal_stale?
      proposal = evidence.proposal
      current = SeasonMembershipProposal.new(
        season, source_year: proposal.fetch('source_year', season.year),
                provider: proposal.fetch('provider', 'sports_reference')
      ).fingerprint
      proposal.fetch('fingerprint') != current
    end
  end

  # Checks whether one retained membership decision still matches its target-season assignment.
  class MembershipDecisionCurrent
    def initialize(season, decision)
      @season = season
      @decision = decision
    end

    def call
      team = Team.find(decision.fetch('team_id'))
      memberships = team.team_conferences.select { |membership| membership.covers_year?(season.year) }
      return false if memberships.many?

      matches_choice?(memberships.map(&:conference_id).first)
    end

    private

    attr_reader :season, :decision

    def matches_choice?(conference_id)
      choice = decision.fetch('choice')
      expected_choice = %w[excluded independent].include?(choice) ? '' : choice.to_s

      conference_id.to_s == expected_choice
    end
  end

  # Captures the approved revision beside the latest recruiting attempt.
  RecruitingEvidence = Data.define(:batch, :revision, :report, :stale, :coverage) do
    def stale_report?
      report != revision.payload.fetch('review').except('review_status', 'approval') ||
        coverage.pointed != coverage.total || pending_batch?
    end

    def pending_batch?
      batch&.status == 'ready' && batch.revision_id != revision.id
    end

    def ensure_revision_valid
      return if revision.valid?

      raise ArgumentError, "approved revision is invalid: #{revision.errors.full_messages.join(', ')}"
    end

    def batch_summary
      latest_batch = batch
      return 'No recruiting batch is stored.' unless latest_batch

      id, status, source_status, failure = latest_batch.attributes.values_at('id', 'status', 'source_status', 'failure_message')
      error = " Fetch error: #{failure}." if failure.present?
      "Latest batch ##{id}: #{status} (#{source_status || 'no source result'}).#{error}"
    end

    def mapping_summary
      rows, omitted_teams = report.values_at('eligible_rows', 'omitted_stored_team_ids')
      "Approved report covers #{rows} mappings and omits #{omitted_teams.size} stored teams."
    end
  end

  # Coverage counts retained profile pointers against all target team seasons.
  RecruitingCoverage = Data.define(:total, :pointed)

  # Recruiting approval remains complete only while retained rows and profile pointers still agree.
  class Recruiting
    def initialize(season)
      @season = season
    end

    def call
      load_latest_evidence
      return missing_approval unless evidence.revision

      build_approval_step
    rescue ArgumentError, KeyError, ActiveRecord::RecordNotFound => error
      Step.new(key: 'recruiting', label: 'Review recruiting inputs', status: 'needs_review',
               last_result: "Retained approval cannot be verified: #{error.message}", next_action: action)
    end

    private

    attr_reader :season, :evidence

    def load_latest_evidence
      @evidence = RecruitingEvidence.new(batch: RecruitingBatch.where(season:).order(id: :desc).first,
                                         revision: OffseasonInputRevision.where(season:, kind: 'recruiting').order(id: :desc).first,
                                         report: nil, stale: false, coverage: nil)
    end

    def missing_approval
      Step.new(key: 'recruiting', label: 'Review recruiting inputs', status: 'needs_review',
               last_result: "No approved recruiting revision is stored. #{evidence.batch_summary}", next_action: action)
    end

    def build_approval_step
      @evidence = evidence.with(report: current_report, coverage: profile_coverage)
      @evidence = evidence.with(stale: report_stale?)
      status = !evidence.stale && supported_year? ? 'complete' : 'needs_review'
      Step.new(key: 'recruiting', label: 'Review recruiting inputs', status:, last_result: approval_result,
               next_action: action)
    end

    def current_report
      revision = evidence.revision
      evidence.ensure_revision_valid
      ::Recruiting::BatchReview.new(approved_batch_for(revision)).report.except('review_status', 'approval')
    end

    def approved_batch_for(revision)
      batch = RecruitingBatch.find_by!(revision_id: revision.id)
      raise ArgumentError, 'approved batch identity does not match revision' unless batch.season_id == season.id
      raise ArgumentError, 'approved batch is not published' unless batch.status == 'published'

      batch
    end

    def report_stale?
      evidence.stale_report?
    end

    def profile_coverage
      team_seasons = TeamSeason.where(season:)
      total = team_seasons.count
      pointed = TeamOffseasonProfile.where(
        team_season_id: team_seasons.select(:id), recruiting_revision_id: evidence.revision.id
      ).count
      RecruitingCoverage.new(total:, pointed:)
    end

    def approval_result
      coverage = evidence.coverage
      ["Approved revision ##{evidence.revision.id} retained.", evidence.batch_summary,
       "Coverage: #{coverage.pointed} of #{coverage.total} team seasons point to this revision.",
       evidence.mapping_summary, freshness_summaries].compact_blank.flatten.join(' ')
    end

    def freshness_summaries
      batch = evidence.batch
      [
        ('Current review is stale: source rows, mappings or profile pointers differ.' if evidence.stale),
        ("Latest batch ##{batch.id} is ready for review; retained approval remains separate." if evidence.pending_batch?),
        ('Recruiting source year is unsupported; use manual review.' unless supported_year?)
      ]
    end

    def supported_year?
      (1901..2201).cover?(season.year)
    end

    def action
      return 'Review the latest captured batch and confirm full target-season coverage.' if supported_year?

      'Recruiting source capture does not support this target year; review inputs manually.'
    end
  end

  # Coaching readiness is read from its persisted review and current candidate set.
  class Coaching
    # Stores one annual review and the number of candidates awaiting a decision.
    Evidence = Data.define(:review, :pending)

    def initialize(season)
      @season = season
    end

    def call
      year = season.year
      review = CoachingReview.find_by(year:)
      pending = CoachingChange.where(effective_year: year, status: 'pending').count
      @evidence = Evidence.new(review:, pending:)
      Step.new(key: 'coaching', label: 'Review coaching changes', status: readiness_status,
               last_result: coaching_result,
               next_action: 'Inspect all candidates and mark the year ready after confirming or rejecting each one.')
    end

    private

    attr_reader :season, :evidence

    def readiness_status
      review = evidence.review
      return 'needs_review' unless review&.ready? && evidence.pending.zero?
      return 'needs_review' if review.discovery_status.in?(%w[queued fetching failed])

      'complete'
    end

    def coaching_result
      details = evidence.review&.attributes&.values_at('discovery_status', 'discovered_at', 'discovery_error') || []
      status, discovered_at, error = details
      status ||= 'not started'
      error_summary = " Last discovery error: #{error}." if error.present?
      ["Discovery #{status}; #{evidence.pending} pending candidates.",
       discovered_at && " Last successful discovery: #{discovered_at}.",
       error_summary].compact.join
    end
  end
end
