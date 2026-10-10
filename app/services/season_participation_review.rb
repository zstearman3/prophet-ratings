# frozen_string_literal: true

# Explicit operator evidence; standings and historical storage never decide participation.
class SeasonParticipationReview
  STATUSES = %w[included excluded unresolved].freeze

  def initialize(season)
    @season = season
  end

  def apply(document)
    self.class.validate_document(document)
    Season.with_ratings_lock do
      @season.with_lock do
        @season.update!(participation_review: document) unless @season.participation_review == document
      end
    end
  end

  def validate
    document = @season.participation_review
    return if document.blank?

    self.class.validate_document(document)
    problems = roster_problems + date_problems
    raise ArgumentError, "Season #{@season.id} readiness: #{problems.join('; ')}" if problems.any?
  end

  def validate_activation
    validate
    problems = rating_problems
    raise ArgumentError, "Season #{@season.id} readiness: #{problems.join('; ')}" if problems.any?
  end

  def validate_publication(version, date)
    validate
    return if @season.participation_review.blank?
    return unless publication_conflict?(version, date)

    raise ArgumentError, 'Reviewed participation differs from published outputs. Preserve saved predictions/snapshots; ' \
                         'use deliberate new-version publication and the documented scoped model-switch workflow.'
  end

  def publication_key
    return if @season.participation_review.blank?

    Digest::SHA256.hexdigest(@season.rating_team_seasons.order(:team_id).pluck(:team_id).to_json)
  end

  def self.valid_document?(document)
    document.is_a?(Hash) && document['evidence'].present? && document['reviewed_by'].present? &&
      document['dates'].is_a?(Hash) && document['teams'].is_a?(Array) && document['unresolved_identities'].is_a?(Array)
  end

  def self.validate_document(document)
    raise ArgumentError, 'Roster requires evidence, reviewed_by, dates, teams and unresolved_identities.' unless valid_document?(document)

    ids = document.fetch('teams').map do |entry|
      validate_entry(entry)
      entry.fetch('team_id')
    end
    raise ArgumentError, 'Duplicate roster team IDs; resolve identities before saving review.' unless ids.uniq == ids
  end

  def self.validate_entry(entry)
    id = entry['team_id'] if entry.is_a?(Hash)
    return if id.is_a?(Integer) && id.positive? &&
              STATUSES.include?(entry['status']) && entry['reason'].present?

    raise ArgumentError, 'Each roster entry requires a positive integer team_id, included/excluded/unresolved status and reason.'
  end

  def self.problem(ids, action)
    "#{action} #{ids.inspect}" if ids.any?
  end

  def self.valid_ratings?(row)
    offense, defense, pace = row.attributes.values_at('adj_offensive_efficiency', 'adj_defensive_efficiency', 'adj_pace')
    [offense, defense, pace].all? { |value| value&.finite? } && pace.positive?
  end

  private

  def publication_conflict?(version, date)
    snapshots = @season.team_rating_snapshots.where(ratings_config_version: version)
    date_conflict = snapshots.where(snapshot_date: date).where.not(team_id: @season.rating_team_seasons.select(:team_id)).exists?
    date_conflict || prediction_roster_conflict?(snapshots, version)
  end

  def prediction_roster_conflict?(snapshots, version)
    predictions = @season.predictions.where(ratings_config_version: version)
    referenced = snapshots.where(id: predictions.select(:home_team_snapshot_id))
                          .or(snapshots.where(id: predictions.select(:away_team_snapshot_id)))
    referenced.exists?(["stats ->> 'participation_key' IS DISTINCT FROM ?", publication_key])
  end

  def entries
    @season.participation_review.fetch('teams')
  end

  def roster_problems
    listed_ids = entries.pluck('team_id')
    unresolved_ids = entries.select { |entry| entry['status'] == 'unresolved' }.pluck('team_id') |
                     Team.where.not(id: listed_ids).ids
    reporter = self.class
    [reporter.problem(unresolved_ids.sort, 'Review unresolved participation team IDs'),
     reporter.problem(listed_ids - Team.where(id: listed_ids).ids, 'Resolve unknown team IDs'),
     reporter.problem(@season.participation_review.fetch('unresolved_identities'), 'Resolve roster identities'),
     *included_problems].compact
  end

  def included_problems
    included_ids = entries.select { |entry| entry['status'] == 'included' }.pluck('team_id')
    missing_aliases = included_ids - TeamAlias.where(team_id: included_ids).where.not(value: [nil, '']).distinct.pluck(:team_id)
    reporter = self.class
    [('Include at least one verified participant' if included_ids.empty?),
     reporter.problem(included_ids - @season.team_seasons.pluck(:team_id), 'Run season:prepare for missing included TeamSeason team IDs'),
     reporter.problem(missing_aliases, 'Add/review aliases for included team IDs')].compact
  end

  def date_problems
    dates = @season.participation_review.fetch('dates')
    first = @season.start_date
    last = @season.end_date
    return [] if dates['evidence'].present? && dates['start_date'] == first.iso8601 &&
                 dates['end_date'] == last.iso8601 && first < last

    ['Review current start/end dates and record matching ISO dates plus evidence; inherited defaults are not reviewed dates']
  end

  def rating_problems
    @season.rating_team_seasons.filter_map do |row|
      next if self.class.valid_ratings?(row)

      "Initialize/review finite offense, defense and positive pace for included team ID #{row.team_id} (TeamSeason #{row.id})"
    end
  end
end
