# frozen_string_literal: true

# Retains bounded acquisition intent and committed per-date import evidence.
class ScheduleRefreshRun < ApplicationRecord
  IDENTITY = %w[season_id requested_by_id retry_of_id provider start_date end_date requested_dates max_requests retries].freeze
  TERMINAL = %w[succeeded incomplete failed].freeze
  belongs_to :season
  belongs_to :requested_by, class_name: 'User'
  belongs_to :retry_of, class_name: 'ScheduleRefreshRun', optional: true
  validates :provider, inclusion: { in: %w[sports_reference cbbd] }
  validates :status, inclusion: { in: %w[queued running succeeded incomplete failed] }
  validates :max_requests, numericality: { only_integer: true, greater_than: 0 }, if: :cbbd?
  validates :retries, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }, if: :cbbd?
  validate :valid_window, on: :create
  before_update :preserve_scope

  def self.listing(season_id)
    seasons = Season.order(year: :desc)
    season = season_id.present? ? seasons.find(season_id) : seasons.first
    { seasons:, season:, runs: where(season:).order(id: :desc).limit(30),
      readiness: season && ScheduleReadiness.new(season) }
  end

  def checkpoint(day)
    evidence = report.deep_dup
    evidence['days'] = report.fetch('days', []).reject { |row| row['date'] == day['date'] } + [day]
    update!(report: evidence)
  end

  def report_game_ids
    report.fetch('absent_ids', []) + report.fetch('days', []).flat_map { |day| self.class.day_game_ids(day) }
  end

  def rejection_observations
    ids = report.fetch('days', []).flat_map { |day| day.fetch('rejection_observation_ids', []) }
    GameObservation.where(id: ids, provider:, accepted: false, game_id: nil, outcome: Ingestion::GameSyncProvider::HELD)
                   .where("normalized_payload ->> 'season_year' = ?", season.year.to_s)
                   .where("normalized_payload ->> 'schedule_date' IN (?)", requested_dates).index_by(&:id)
  end

  def self.day_game_ids(day)
    day.fetch('games', []).flat_map { |game| [game['game_id'], *game.fetch('possible_move_ids', [])] }.compact
  end

  def cbbd?
    provider == 'cbbd'
  end

  def pending_dates
    successful = report.fetch('days', []).reject { |day| day['error'] }.pluck('date')
    requested_dates - successful
  end

  def build_retry(user)
    with_lock do
      raise ArgumentError, 'Retry requires a terminal run; refresh the running report first.' unless TERMINAL.include?(status)
      raise ArgumentError, 'No failed or unattempted dates remain.' if pending_dates.empty?

      self.class.new(season:, requested_by: user, retry_of: self, provider:, max_requests:, retries:,
                     start_date: pending_dates.min, end_date: pending_dates.max, requested_dates: pending_dates)
    end
  end

  def finish(state, message = nil)
    update!(status: state, error: message, finished_at: Time.current)
  end

  private

  def preserve_scope
    raise ActiveRecord::ReadOnlyRecord, 'Run scope is immutable' if IDENTITY.any? { |field| will_save_change_to_attribute?(field) }
  end

  def valid_window
    first = Ingestion::HistoricalSyncWindow.parse_date(start_date_before_type_cast.to_s)
    last = Ingestion::HistoricalSyncWindow.parse_date(end_date_before_type_cast.to_s)
    self.requested_dates = requested_dates.presence || (first..last).map(&:iso8601)
    validate_dates(first, last)
  rescue ArgumentError, TypeError
    errors.add(:base, 'Use ordered ISO dates today or later inside the target season; use historical sync for expired dates.')
  end

  def validate_dates(first, last)
    ordered = season && first <= last && first >= season.start_date && last <= season.end_date
    unique = requested_dates.present? && requested_dates.uniq == requested_dates
    raise ArgumentError unless ordered && unique && dates_inside?(first..last)
  end

  def dates_inside?(window)
    requested_dates.all? do |value|
      date = Ingestion::HistoricalSyncWindow.parse_date(value)
      window.cover?(date) && date >= Game.current_schedule_date
    end
  end
end
