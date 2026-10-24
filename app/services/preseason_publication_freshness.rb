# frozen_string_literal: true

# Conservative dependency stamp for dashboard freshness, without loading source payloads
# or calculating ratings. Immutable revisions are represented by their stored identities.
class PreseasonPublicationFreshness
  def initialize(season, ratings_config_version:)
    @season = season
    @model = ratings_config_version
  end

  def call
    evidence = scopes.map { |scope| self.class.row_hashes(scope) }
    evidence << PreseasonPrior.where(team_season: season.team_seasons, ratings_config_version: model).order(:id).pluck(:id)
    Digest::SHA256.hexdigest(evidence.to_json)
  end

  private

  attr_reader :season, :model

  def scopes
    year = season.year
    years = [year, year - 1] + CoachingChange.where(effective_year: year).distinct.pluck(:previous_year).compact
    history = Season.where(year: years)
    rows = TeamSeason.where(season: history)
    [history, rows, Team.all, TeamAlias.all, TeamOffseasonProfile.where(team_season: season.team_seasons),
     *coaching_scopes]
  end

  def coaching_scopes
    return [] unless model.settings.dig(:preseason, :coaching)

    year = season.year
    [CoachingReview.where(year:), CoachingChange.where(effective_year: year)]
  end

  public_class_method def self.row_hashes(scope)
    table = scope.klass.quoted_table_name
    # Hash each row inside PostgreSQL so large JSON evidence never enters the web process.
    scope.order(:id).pluck(:id, Arel.sql("md5(row_to_json(#{table})::text)"))
  end
end
