# frozen_string_literal: true

# Decorates existing immutable calculations; current evidence is separate from reused capture evidence.
class PreseasonPublicationPreview
  def initialize(season, ratings_config_version:, mode:, reviewed_revisions: ProphetRatings::ReviewedInputRevisions.new)
    @season = season
    @model = ratings_config_version
    @mode = mode
    @reviewed_revisions = reviewed_revisions
    raise ArgumentError, 'Choose initialize or revise.' unless mode.in?(%w[initialize revise])
  end

  def call
    season.with_lock do
      validate_mode
      raise ArgumentError, 'No included teams; prepare and review the target-season roster first.' unless season.rating_team_seasons.exists?

      with_coaching_review { build_report }
    end
  end

  def calculation
    service = mode == 'revise' ? ProphetRatings::PreseasonRevision : ProphetRatings::PreseasonInitializer
    service.new(season, ratings_config_version: model, reviewed_revisions: @reviewed_revisions)
  end

  # Saved pages need provenance and component results, not every replay operand for every team.
  def self.presentation(report)
    return report unless report['teams']

    teams = report.fetch('teams').map { |entry| presentation_team(entry) }
    report.merge('teams' => teams, 'largest_movers' => largest_movers(teams))
  end

  def self.presentation_team(entry)
    inputs = entry.fetch('inputs')
    facts = inputs.slice('contract', 'team_id', 'target_year', 'baselines', 'baseline_sources', 'previous_values',
                         'profile_values', 'coaching')
    facts.merge!(presentation_sources(inputs), presentation_revisions(inputs))
    entry.except('profile_before', 'profile_after', 'outputs_before', 'outputs_after').merge('inputs' => facts)
  end

  def self.presentation_revisions(inputs)
    { 'reviewed_recruiting' => inputs['reviewed_recruiting']&.slice('revision', 'review', 'status', 'class_points', 'units', 'row'),
      'reviewed_departures' => inputs['reviewed_departures']&.slice('revision', 'review') }
      .transform_values { |evidence| ProphetRatings::ReviewedInputRevisions.compact_evidence(evidence) }
  end

  def self.presentation_sources(inputs)
    %w[previous_season previous_team_season profile].index_with { |key| inputs[key]&.slice('id', 'updated_at') }
  end

  private

  attr_reader :season, :model, :mode

  def validate_mode
    revision = season.preseason_revision_id
    return if mode != 'initialize' || revision.blank? || revision == model.id

    raise ArgumentError, "Season has explicit preseason revision ##{revision}; choose explicit revise with an eligible " \
                         'already-published unused model to change models. Initialize only repeats the same revision model.'
  end

  def with_coaching_review(&)
    return yield unless model.settings.dig(:preseason, :coaching)

    ProphetRatings::CoachingPaceInputs.new(season).with_review(&)
  end

  def build_report
    report = calculation.preview.deep_stringify_keys!.merge(report_identity)
    teams = decorated_teams(report.fetch('teams'))
    report.merge!('teams' => teams, 'gaps' => teams.flat_map { |entry| PreseasonPublicationGaps.new(entry).call },
                  'largest_movers' => self.class.largest_movers(teams))
    report.merge('fingerprint' => fingerprint(report))
  end

  def report_identity
    { 'mode' => mode, 'model_id' => model.id, 'model_version' => model.name,
      'selection_generation' => season.preseason_selection_generation,
      'coverage' => { 'included' => season.rating_team_seasons.count, 'stored' => season.team_seasons.count } }
  end

  def decorated_teams(entries)
    rows = season.rating_team_seasons.includes(:team).index_by(&:id)
    decorated = entries.map do |entry|
      PreseasonPublicationTeam.new(entry, rows.fetch(entry.fetch('team_season_id')), model, mode).call
    end
    self.class.assign_ranks(decorated)
    decorated
  end

  public_class_method def self.largest_movers(entries)
    entries.select { |entry| entry['rank_change'] }.sort_by { |entry| [-entry.fetch('rank_change').abs, entry['team_id']] }.first(10)
  end

  public_class_method def self.assign_ranks(entries)
    entries.sort_by { |entry| [-entry.dig('after', 'net'), entry['team_id']] }.each.with_index(1) do |entry, rank|
      entry['after']['rank'] = rank
      previous = entry.dig('before', 'rank')
      entry['rank_change'] = previous - rank if previous
    end
  end

  def coaching_review_identity
    CoachingReview.find_by(year: season.year)&.attributes if model.settings.dig(:preseason, :coaching)
  end

  def current_input_hashes(calculator)
    season.rating_team_seasons.order(:team_id).map do |row|
      Departures::Contract.digest(calculator.preview_inputs(row).as_json)
    end
  end

  def fingerprint(report)
    calculator = ProphetRatings::PreseasonRatingsCalculator.new(season, ratings_config_version: model,
                                                                        reviewed_revisions: @reviewed_revisions)
    evidence = { report: ProphetRatings::PreseasonReportBuilder.fingerprint(report), model: model.config,
                 coaching_review: coaching_review_identity, season: season.attributes.except('updated_at'),
                 roster: season.team_seasons.order(:id).map(&:attributes),
                 current_inputs: current_input_hashes(calculator) }
    Departures::Contract.digest(evidence.as_json)
  end
end
