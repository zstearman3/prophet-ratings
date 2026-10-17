# frozen_string_literal: true

module Coaching
  # Year-scoped, preview-bound edits reuse the existing fact and readiness validations.
  class YearReview
    EDITABLE_FIELDS = %w[team_id coach_name previous_team_id previous_year previous_role
                         full_season_head_coach previous_season_d1 status].freeze

    attr_reader :year

    def initialize(year)
      @year = Integer(year.to_s, 10)
      raise ArgumentError, 'Year must be between 2 and 9999.' unless (2..9999).cover?(@year)
    end

    def review
      CoachingReview.find_by(year:) || CoachingReview.new(year:)
    end

    def candidates
      CoachingChange.where(effective_year: year).includes(:team, :previous_team)
                    .order(Arel.sql("CASE WHEN status = 'pending' THEN 0 ELSE 1 END"), :id).to_a
    end

    def review_key
      Departures::Contract.digest([year, review.attributes, CoachingChange.where(effective_year: year).order(:id).map(&:attributes),
                                   Team.order(:id).pluck(:id, :school)])
    end

    def save(attributes, intent:)
      transaction do
        validate_submission(attributes, intent)
        save_rows(attributes.fetch('rows', {}))
        record = CoachingReview.find_or_create_by!(year:)
        record.update!(ready: true) if intent == 'ready'
      end
    end

    def queue_discovery
      transaction { CoachingReview.find_or_create_by!(year:).queue_discovery }
    end

    def page(number)
      rows = candidates
      teams = Team.order(:school).pluck(:school, :id)
      self.class.pagination(rows, number).merge(state: review, candidates: rows, teams:,
                                                team_names: teams.to_h { |school, id| [id, school] },
                                                source_url: Scraper::CoachingChangesScraper.new(year:).source_url)
    end

    def self.pagination(rows, number)
      count = [(rows.size / 25.0).ceil, 1].max
      current = number.to_i.clamp(1, count)
      { page_count: count, page_number: current, page_rows: rows.slice((current - 1) * 25, 25) || [] }
    end

    def add_candidate
      CoachingChange.create!(effective_year: year)
    end

    def self.save_row(candidate, values)
      candidate.assign_attributes(values.slice(*EDITABLE_FIELDS))
      candidate.reconfirm = true
      candidate.save!
    end

    def self.source_warnings(candidate)
      return ['Manual candidate'] if candidate.discovery_school.blank?

      discovered_team = candidate.discovery_team_id
      {
        'Absent from latest successful source fetch' => !candidate.discovery_present?,
        'Source incoming coach differs from saved facts' => CoachingChangeMatch.normalize(candidate.coach_name) !=
          CoachingChangeMatch.normalize(candidate.discovery_coach_name),
        'Source destination differs or is unresolved' => discovered_team.blank? || candidate.team_id != discovered_team,
        'Source previous team differs from saved history' => candidate.previous_team_id != candidate.discovery_previous_team_id
      }.select { |_warning, changed| changed }.keys
    end

    def self.validate_row_keys(rows, keys)
      return if rows.is_a?(Hash) && (rows.keys - keys).empty?

      raise ArgumentError, 'Save only coaching candidates from this year.'
    end

    private

    def transaction(&)
      CoachingReview.transaction { CoachingReview.with_year_locks([year], &) }
    end

    def validate_submission(attributes, intent)
      raise ArgumentError, 'Choose save or mark ready.' unless intent.in?(%w[save ready])
      raise ArgumentError, 'Confirm that you reviewed these coaching facts and decisions.' unless attributes['confirm'] == '1'
      raise ArgumentError, 'Coaching review changed; reload and review again.' unless attributes['review_key'] == review_key
      return unless intent == 'ready' && review.discovery_status.in?(%w[queued fetching failed])

      raise ArgumentError, 'Finish a successful discovery before marking this year ready.'
    end

    def save_rows(rows)
      records = candidates.index_by(&:id).transform_keys(&:to_s)
      converter = self.class
      converter.validate_row_keys(rows, records.keys)
      rows.each { |id, values| converter.save_row(records.fetch(id), values) }
    end
  end
end
