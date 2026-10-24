# frozen_string_literal: true

# A read-only decision surface, including after publication and activation.
class OffseasonReadiness
  LABELS = {
    'model' => 'Selected model', 'publication' => 'Applied captures, core outputs and preopening snapshot ranks',
    'coaching' => 'Applicable coaching readiness', 'schedule' => 'Schedule and reconciliation', 'venues' => 'Venue evidence',
    'predictions' => 'Stored prediction coverage for selected model', 'operations' => 'Latest stored operation results'
  }.freeze
  REQUIRED = %w[memberships model publication coaching].freeze

  def initialize(season)
    @season = season
    @reviewed_revisions = ProphetRatings::ReviewedInputRevisions.new
  end

  def call
    season.reload
    @evidence = OffseasonReadinessEvidence.new(season, reviewed_revisions: @reviewed_revisions)
    gaps = publication.gaps
    report = identity.merge('checks' => checks, 'gaps' => gaps, 'teams' => publication.team_evidence).as_json
    report.merge('fingerprint' => evidence.fingerprint(report))
  end

  def self.from_step(step)
    key = step.key
    { 'key' => key, 'label' => step.label, 'status' => step.status == 'complete' ? 'pass' : 'open',
      'evidence' => step.last_result, 'hard' => REQUIRED.include?(key) }
  end

  private

  attr_reader :season, :evidence

  def identity
    { 'season_id' => season.id, 'year' => season.year, 'dates' => [season.start_date, season.end_date],
      'model_id' => model&.id, 'model_name' => model&.name,
      'current_season_id' => Season.current&.id, 'default_model_id' => RatingsConfigVersion.published_default&.id }
  end

  def model
    season.selected_preseason_model
  end

  def publication
    @publication ||= OffseasonReadinessPublication.new(season, model, reviewed_revisions: @reviewed_revisions)
  end

  def checks
    [OffseasonReadiness.from_step(OffseasonSetupProgress::Memberships.new(season).call), model_check, publication_check,
     coaching_check, *input_checks, *operational_checks]
  end

  public_class_method def self.check(key, status, evidence)
    { 'key' => key, 'label' => LABELS.fetch(key), 'status' => status, 'evidence' => evidence, 'hard' => REQUIRED.include?(key) }
  end

  def model_check
    raise ArgumentError, 'Select a persisted published model in preseason review.' unless model

    model.settings
    OffseasonReadiness.check('model', 'pass', "#{model.name} (##{model.id}); selection generation #{season.preseason_selection_generation}")
  rescue ArgumentError => error
    OffseasonReadiness.check('model', 'open', error.message)
  end

  def publication_check
    problems = publication.problems
    OffseasonReadiness.check('publication', problems.empty? ? 'pass' : 'open', problems.presence || publication.summary)
  end

  def coaching_check
    OffseasonReadiness.check('coaching', 'pass', coaching_summary)
  rescue ArgumentError => error
    OffseasonReadiness.check('coaching', 'open', error.message)
  end

  def coaching_summary
    raise ArgumentError, 'Select a model to determine applicable coaching requirements.' unless model
    return 'Selected contract does not require coaching inputs.' unless model.settings.dig(:preseason, :coaching)

    ProphetRatings::CoachingPaceInputs.new(season).validate_readiness
    'Annual review ready; no pending candidates.'
  end

  def input_checks
    [OffseasonSetupProgress::Recruiting.new(season).call, DepartureProgress.new(season).call].map do |step|
      OffseasonReadiness.from_step(step)
    end
  end

  def operational_checks
    schedule = ScheduleReadiness.new(season)
    operations = evidence
    [OffseasonReadiness.check('schedule', schedule.usable? ? 'pass' : 'open', schedule.summary), venue_check, prediction_check,
     OffseasonReadiness.check('operations', operations.operation_status, operations.operation_summary)]
  end

  def venue_check
    games = season.games
    total = games.count
    unknown = unknown_venues
    OffseasonReadiness.check('venues', total.positive? && unknown.zero? ? 'pass' : 'open',
                             "#{unknown} unknown venues among #{total} games.")
  end

  def unknown_venues
    season.games.where('venue_type = ? OR venue_confidence = ?', 'unknown', 'unknown').count
  end

  def prediction_check
    count = season.predictions.where(ratings_config_version_id: model&.id).distinct.count(:game_id)
    total = season.games.count
    OffseasonReadiness.check('predictions', ScheduleReadiness.new(season).usable? && total.positive? && count == total ? 'pass' : 'open',
                             "#{count} of #{total} games have stored predictions for the selected model; no accuracy certification.")
  end
end
