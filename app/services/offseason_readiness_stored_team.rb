# frozen_string_literal: true

# The capture applied to one team and its preopening publication remain inspectable in season.
class OffseasonReadinessStoredTeam
  CORE = %w[adj_offensive_efficiency adj_defensive_efficiency adj_pace].freeze

  def initialize(row, model, snapshot:)
    @row = row
    @model = model
    @snapshot = snapshot
  end

  def problems
    return [problem('missing matching applied capture or snapshot; publish selected model.')] unless
      prior&.ratings_config_version_id == model.id && snapshot

    [applied_problem, provenance_problem, core_problem].compact
  end

  def evidence
    team = row.team
    { 'team_id' => row.team_id, 'team_name' => team.school, 'aliases' => team.team_aliases.order(:id).pluck(:value),
      'team_season_id' => row.id, 'live_model_id' => row.ratings_config_version_id, 'live_rank' => row.overall_rank,
      'capture_id' => prior&.id, 'capture_model_id' => prior&.ratings_config_version_id, 'capture_outputs' => prior&.outputs,
      'snapshot' => snapshot&.attributes&.except('stats', 'readiness_capture_matches'), 'snapshot_rank' => snapshot&.overall_rank }
  end

  def gaps(calculator)
    captured_gaps + current_gaps(calculator)
  end

  def self.with_prior(row, scope)
    association = row.association(:preseason_prior)
    association.target = PreseasonPrior.uncached { scope.find_by(id: row.preseason_prior_id) }
    yield
  ensure
    association&.reset
  end

  private

  attr_reader :row, :model, :snapshot

  def captured_gaps
    source_gaps('captured', prior&.inputs)
  rescue ArgumentError, KeyError => error
    verification_gap('captured', error)
  end

  def current_gaps(calculator)
    source_gaps('current', calculator.preview_inputs(row).deep_stringify_keys)
  rescue ArgumentError, KeyError => error
    verification_gap('current', error)
  end

  def verification_gap(source, error)
    [{ 'team_id' => row.team_id, 'team_name' => row.team.school, 'source' => source, 'kind' => 'inputs',
       'reason' => "#{source.humanize} inputs cannot be verified: #{error.message}" }]
  end

  def prior
    row.preseason_prior
  end

  def problem(message)
    "Team #{row.team_id}: #{message}"
  end

  def applied_problem
    return if row.matching_prior?(model.id)

    problem('capture outputs differ from applied preseason values.')
  end

  def provenance_problem
    return projected_provenance_problem if snapshot.has_attribute?(:readiness_capture_matches)

    evidence = snapshot.stats['preseason_prior']
    return if evidence && evidence['id'] == prior.id && evidence['inputs'] == prior.inputs && evidence['outputs'] == prior.outputs

    problem('snapshot capture identity/values differ.')
  end

  def projected_provenance_problem
    problem('snapshot capture identity/values differ.') unless snapshot[:readiness_capture_matches] == true
  end

  def core_problem
    return if CORE.all? { |stat| core_matches?(stat) }

    problem('snapshot core outputs differ from captured outputs.')
  end

  def core_matches?(stat)
    actual = snapshot.public_send(stat)
    expected = prior.outputs["preseason_#{stat}"]
    actual&.finite? && actual == expected && (stat != 'adj_pace' || actual.positive?)
  end

  def source_gaps(source, inputs)
    return [] unless inputs

    entry = ProphetRatings::PreseasonReportBuilder.new(row, inputs, model.config, prior:).call.deep_stringify_keys
    entry['team_name'] = row.team.school
    PreseasonPublicationGaps.new(entry).call.map { |gap| gap.merge('source' => source) }
  end
end
