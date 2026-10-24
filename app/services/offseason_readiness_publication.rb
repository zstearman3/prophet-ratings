# frozen_string_literal: true

# Validates concrete stored provenance without invoking protected publication previews.
class OffseasonReadinessPublication
  CAPTURE_MATCH_SQL = <<~SQL.squish.freeze
    (team_rating_snapshots.stats #> '{preseason_prior,id}' = to_jsonb(preseason_priors.id)
     AND team_rating_snapshots.stats #> '{preseason_prior,inputs}' = preseason_priors.inputs
     AND team_rating_snapshots.stats #> '{preseason_prior,outputs}' = preseason_priors.outputs) AS readiness_capture_matches
  SQL

  def initialize(season, model, reviewed_revisions: ProphetRatings::ReviewedInputRevisions.new)
    @season = season
    @model = model
    @reviewed_revisions = reviewed_revisions
  end

  def problems
    validate_coverage
    [*rows.flat_map { |row| with_stored_team(row, self.class.prior_metadata, &:problems) }, *rank_problems]
  rescue ArgumentError, KeyError => error
    [error.message]
  end

  def team_evidence
    rows.map { |row| with_stored_team(row, self.class.prior_metadata, &:evidence) }
  end

  def summary
    "#{rows.size} included teams; model ##{model.id}; captures #{rows.map(&:preseason_prior_id)}; " \
      "snapshots #{snapshots.map(&:id)} dated #{season.start_date - 1.day}."
  end

  def gaps
    return [] unless model

    rows.flat_map { |row| team_gaps(row) }.uniq
  end

  private

  attr_reader :season, :model

  def validate_coverage
    raise ArgumentError, 'Select and publish the target model.' unless model

    review = SeasonParticipationReview.new(season)
    review.validate_activation
    review.validate_revision(model)
    raise ArgumentError, 'No included teams have published outputs.' if rows.empty?
  end

  def rows
    @rows ||= season.rating_team_seasons.includes(:team).order(:team_id).to_a
  end

  def snapshots
    @snapshots ||= season.team_rating_snapshots.where(ratings_config_version: model,
                                                      snapshot_date: season.start_date - 1.day)
                         .joins(:team_season).joins('LEFT JOIN preseason_priors ON preseason_priors.id = team_seasons.preseason_prior_id')
                         .select(*self.class.snapshot_columns, Arel.sql(CAPTURE_MATCH_SQL)).order(:team_id).to_a
  end

  public_class_method def self.snapshot_columns
    columns = TeamRatingSnapshot.column_names.excluding('stats').map { |name| "team_rating_snapshots.#{name}" }
    columns + [Arel.sql("team_rating_snapshots.stats - 'preseason_prior' AS stats")]
  end

  public_class_method def self.prior_metadata
    PreseasonPrior.select(:id, :team_season_id, :ratings_config_version_id, :outputs)
  end

  def with_stored_team(row, scope)
    OffseasonReadinessStoredTeam.with_prior(row, scope) { yield stored_team(row) }
  end

  def team_gaps(row)
    with_stored_team(row, PreseasonPrior.all) { |team| team.gaps(calculator) }
  end

  def stored_team(row)
    snapshot = snapshots.find { |item| item.team_season_id == row.id && item.team_id == row.team_id }
    OffseasonReadinessStoredTeam.new(row, model, snapshot:)
  end

  def rank_problems
    return [] if snapshots.size == rows.size && self.class.ranks_match?(snapshots)

    ['Preopening ranks do not match deterministic net-rating order.']
  end

  public_class_method def self.ranks_match?(snapshots)
    return false unless snapshots.all? { |snapshot| SeasonParticipationReview.valid_ratings?(snapshot) }

    ordered_ranks_match?(snapshots)
  end

  public_class_method def self.ordered_ranks_match?(snapshots)
    ordered = snapshots.sort_by { |snapshot| [-snapshot.rating.to_f, snapshot.team_id] }
    ordered.map(&:overall_rank) == (1..ordered.size).to_a && ordered.all? { |snapshot| valid_net?(snapshot) }
  end

  public_class_method def self.valid_net?(snapshot)
    snapshot.rating == snapshot.adj_offensive_efficiency - snapshot.adj_defensive_efficiency
  end

  def calculator
    @calculator ||= ProphetRatings::PreseasonRatingsCalculator.new(season, ratings_config_version: model,
                                                                           reviewed_revisions: @reviewed_revisions)
  end
end
