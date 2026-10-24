# frozen_string_literal: true

# Stored state participating in this review, excluding review records themselves.
class OffseasonReadinessEvidence
  def initialize(season, reviewed_revisions: ProphetRatings::ReviewedInputRevisions.new)
    @season = season
    @model = season.selected_preseason_model
    @reviewed_revisions = reviewed_revisions
  end

  def fingerprint(report)
    serializer = self.class
    evidence = { report:, season: season.attributes, teams: serializer.records(Team.all), aliases: serializer.records(TeamAlias.all),
                 memberships: serializer.records(TeamConference.all), ratings: rating_evidence, operational: operational_evidence }
    Departures::Contract.digest(evidence.as_json)
  end

  def operations
    @operations ||= [PreseasonPublication, ScheduleRefreshRun, RecruitingBatch, DepartureBatch].filter_map do |type|
      OffseasonReadinessEvidence.latest_operation(type, season)
    end + departure_acquisition
  end

  def operation_status
    states = (operations.presence || [{ 'status' => 'none' }]).pluck('status')
    (states - %w[published succeeded completed]).empty? ? 'pass' : 'open'
  end

  def operation_summary
    operations.presence || 'No operation evidence stored. Inspect GoodJob for worker failures.'
  end

  private

  public_class_method def self.latest_operation(type, season)
    fields = %w[id status source_status error error_message failure_message reviewed_by reviewed_at updated_at] & type.column_names
    row = type.where(season:).select(*fields).order(:id).last
    return unless row

    row.attributes.merge('operation' => type.name)
  end

  attr_reader :season

  public_class_method def self.records(relation)
    PreseasonPublicationFreshness.row_hashes(relation)
  end

  def departure_acquisition
    acquisition = DepartureAcquisition.where(departure_batch: DepartureBatch.where(season:))
                                      .select(:id, :status, :failure, :updated_at).order(:id).last
    return [] unless acquisition

    [acquisition.attributes.slice('id', 'status', 'failure', 'updated_at').merge('operation' => 'DepartureAcquisition')]
  end

  def rating_evidence
    serializer = self.class
    rows = season.team_seasons
    { rows: serializer.records(rows), profiles: serializer.records(TeamOffseasonProfile.where(team_season: rows)),
      priors: serializer.records(PreseasonPrior.where(team_season: rows)), snapshots: serializer.records(season.team_rating_snapshots),
      inputs: serializer.records(OffseasonInputRevision.where(season:)), coaching: coaching, current_inputs: current_inputs }
  end

  def operational_evidence
    serializer = self.class
    games = season.games
    { games: serializer.records(games), predictions: serializer.records(season.predictions),
      publications: serializer.records(season.preseason_publications), operations: operations,
      deferrals: serializer.records(ScheduleDeferral.where(season:)), team_games: serializer.records(TeamGame.where(game: games)) }
  end

  def current_inputs
    return unless @model

    read_current_inputs
  rescue ArgumentError => error
    { error: error.message }
  end

  def read_current_inputs
    calculator = ProphetRatings::PreseasonRatingsCalculator.new(season, ratings_config_version: @model,
                                                                        reviewed_revisions: @reviewed_revisions)
    season.rating_team_seasons.order(:team_id).map { |row| Departures::Contract.digest(calculator.preview_inputs(row).as_json) }
  end

  def coaching
    year = season.year
    { review: CoachingReview.find_by(year:)&.attributes,
      changes: OffseasonReadinessEvidence.records(CoachingChange.where(effective_year: year)) }
  end
end
