# frozen_string_literal: true

# Applies recognized membership switches atomically; structural changes remain suggestions.
class SeasonConferenceAlignment
  # Persistence or identity conflicts that prevent a safe alignment.
  class Error < StandardError
  end

  # All applied changes and unresolved source differences for an admin handoff.
  Result = Data.define(:year, :source_url, :created, :changed, :unchanged, :suggestions) do
    def success?
      suggestions.empty?
    end

    def report_absences(expected, matches)
      report_absent_teams(expected.map(&:team).uniq - matches.flat_map(&:teams))
      report_absent_conferences(expected.map(&:conference).uniq - matches.flat_map(&:conferences))
    end

    def report_absent_teams(absent_teams)
      absent_teams.each do |team|
        suggestions << "absent_team: #{team.school} (id=#{team.id}) has membership in #{year} but is absent from source"
      end
    end

    def report_absent_conferences(absent_conferences)
      absent_conferences.each do |conference|
        suggestions << "absent_conference: #{conference.name} (id=#{conference.id}) " \
                       "has membership in #{year} but is absent from source"
      end
    end
  end

  attr_reader :year

  delegate :source_url, to: :scraper

  def initialize(year: Season.maximum(:year))
    raise ArgumentError, 'No stored season exists. Run season:prepare YEAR=<year> first.' if year.blank?

    @year = Integer(year)
    @season = Season.find_by(year: @year)
    raise ArgumentError, "No season found for year=#{year}. Run season:prepare first." unless @season
  end

  def call
    @result = Result.new(year:, source_url:, created: [], changed: [], unchanged: [], suggestions: [])
    apply_matches(source_matches)
    result
  rescue ActiveRecord::RecordInvalid => error
    raise Error, "Alignment rolled back: #{error.message}"
  end

  private

  attr_reader :season, :result, :target_memberships

  def scraper
    @scraper ||= Scraper::ConferenceStandingsScraper.new(year:)
  end

  def source_matches
    rows = scraper.call
    Scraper::ConferenceStandingsScraper.validate!(rows)
    ConferenceAlignmentMatch.resolve(rows)
  end

  def apply_matches(matches)
    Season.transaction do
      season.lock!
      @target_memberships = active_memberships
      reconcile(matches)
    end
  end

  def reconcile(matches)
    result.report_absences(target_memberships, matches)
    result.suggestions.concat(matches.flat_map(&:suggestions)).uniq!
    matches.filter_map { |match| match.membership(season) }.each { |membership| assign(membership) }
  end

  def active_memberships
    TeamConference.includes(:team, :conference)
                  .joins('INNER JOIN seasons AS alignment_start ON alignment_start.id = team_conferences.start_season_id')
                  .joins('LEFT JOIN seasons AS alignment_end ON alignment_end.id = team_conferences.end_season_id')
                  .where(alignment_start: { year: ..year })
                  .where('alignment_end.id IS NULL OR alignment_end.year >= ?', year).to_a
  end

  def assign(membership)
    team_id = membership.team_id
    existing = target_memberships.find { |candidate| candidate.team_id == team_id }
    reconcile_membership(membership, existing)
  end

  def reconcile_membership(membership, existing)
    label = membership.admin_label
    return result.unchanged << label if existing&.conference_id == membership.conference_id
    return report_conflict(label) if existing&.start_season_id == season.id

    save_membership(membership, existing, label)
  end

  def report_conflict(label)
    result.suggestions << "membership_conflict: #{label}; a different membership already starts in #{year}; correct it manually and rerun"
  end

  def save_membership(membership, existing, label)
    raise ActiveRecord::RecordInvalid, membership unless TeamConferenceAssignment.new(membership).call

    if existing
      result.changed << "#{label} (from #{existing.conference.name})"
    else
      result.created << label
    end
  end
end
