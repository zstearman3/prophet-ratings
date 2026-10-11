# frozen_string_literal: true

# Fetches first, then atomically saves pending proposals under the year review lock.
class CoachingChangesImport
  def initialize(year:, scraper: Scraper::CoachingChangesScraper)
    @year = Integer(year.to_s, 10)
    raise ArgumentError, 'YEAR must be an integer from 2 to 9999' unless (2..9999).cover?(@year)

    @scraper = scraper
  end

  def call
    rows = scraper.new(year:).call
    self.class.validate_rows(rows)
    summary(rows.size, persist_rows(rows))
  end

  def summary(row_count, imported)
    reports, absent_ids = imported
    resolved_count = reports.count { |report| report[:destination_team_ids].one? }
    { year:, d1_rows: row_count, resolved_destinations: resolved_count,
      unresolved_destinations: row_count - resolved_count, absent_candidate_ids: absent_ids, candidates: reports }
  end

  def self.validate_rows(rows)
    raise Scraper::CoachingChangesScraper::Error, 'Malformed coaching rows' unless rows.is_a?(Array) && rows.all?(Hash)

    Scraper::CoachingChangesScraper.validate!(rows.map { |row| { 'value' => row.stringify_keys } })
  end

  def self.mark_absent(candidate)
    candidate.update!(discovery_present: false)
    candidate.id
  end

  private

  attr_reader :year, :scraper

  def mark_absences(rows)
    schools = rows.map { |row| CoachingChangeMatch.normalize(row.fetch(:school)) }
    absent = CoachingChange.where(effective_year: year).where.not(discovery_school: nil).where.not(discovery_school: schools)
    absent.map { |candidate| self.class.mark_absent(candidate) }
  end

  def persist_rows(rows)
    CoachingChange.transaction do
      CoachingReview.with_year_locks([year]) do
        reports = rows.map { |row| CoachingChangeProposal.new(year:, match: CoachingChangeMatch.new(row, rows:)).call }
        [reports, mark_absences(rows)]
      end
    end
  end
end
