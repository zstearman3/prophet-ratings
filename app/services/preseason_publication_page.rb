# frozen_string_literal: true

# Projects legacy and current saved evidence before it crosses the database boundary.
# SQL expressions and field names here are fixed application constants, never user input.
class PreseasonPublicationPage
  REPORT_FIELDS = %w[season_id mode model_id model_version selection_generation coverage gaps fingerprint preview_key].freeze
  TEAM_FIELDS = %w[team_id team_season_id team_name added capture_id reuses_capture before after deltas rank_change
                   fallbacks legacy_components coaching].freeze
  INPUT_FIELDS = %w[contract team_id target_year baselines baseline_sources previous_values profile_values coaching].freeze

  def self.summary(scope)
    project(scope, Arel.sql(SUMMARY_SQL))
  end

  def self.review(scope)
    project(scope, Arel.sql(REVIEW_SQL))
  end

  def self.outputs(publication)
    TeamRatingSnapshot.where(id: publication.result.fetch('snapshot_ids', []), season_id: publication.season_id,
                             ratings_config_version_id: publication.ratings_config_version_id)
                      .select(:id, :team_id, :rating, :adj_offensive_efficiency, :adj_defensive_efficiency, :adj_pace)
                      .includes(:team).order(rating: :desc, team_id: :asc)
  end

  def self.project(scope, projection)
    scope.select(*(PreseasonPublication.column_names - ['report']), projection)
  end

  def self.fields(source, names)
    pairs = names.map { |name| "'#{name}', #{source}->'#{name}'" }.join(', ')
    "jsonb_build_object(#{pairs})"
  end

  def self.team
    "#{fields('entry', TEAM_FIELDS)} || jsonb_build_object('inputs', #{inputs}, 'efficiency', #{efficiency})"
  end

  def self.inputs
    sources = %w[previous_season previous_team_season profile].map do |name|
      "'#{name}', #{fields("entry->'inputs'->'#{name}'", %w[id updated_at])}"
    end
    recruiting = revision("entry->'inputs'->'reviewed_recruiting'", %w[revision status class_points units])
    departures = revision("entry->'inputs'->'reviewed_departures'", %w[revision])
    "#{fields("entry->'inputs'", INPUT_FIELDS)} || jsonb_build_object(#{sources.join(', ')}, " \
      "'reviewed_recruiting', #{recruiting}, 'reviewed_departures', #{departures})"
  end

  def self.revision(source, names)
    review = fields("#{source}->'review'", %w[review_status approval decision reviewed_by reviewed_at version reason
                                              dataset_revision mapping_revision])
    "#{fields(source, names)} || jsonb_build_object('review', #{review})"
  end

  def self.efficiency
    "(entry->'efficiency' || jsonb_build_object(" \
      "'recruiting', (entry->'efficiency'->'recruiting') - 'inputs' - 'configuration', " \
      "'departures', (entry->'efficiency'->'departures') - 'inputs' - 'configuration'))"
  end

  SUMMARY_SQL = "(#{fields('report', REPORT_FIELDS)}) AS report".freeze
  REVIEW_SQL = <<~SQL.squish.freeze
    (#{fields('report', REPORT_FIELDS)} || jsonb_build_object('teams', (
      SELECT COALESCE(jsonb_agg(#{team}), '[]'::jsonb)
      FROM jsonb_array_elements(COALESCE(report->'teams', '[]'::jsonb)) entry
    ))) AS report
  SQL

  private_class_method :project, :fields, :team, :inputs, :revision, :efficiency
end
