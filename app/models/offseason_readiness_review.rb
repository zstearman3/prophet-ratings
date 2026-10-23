# frozen_string_literal: true

# The displayed evidence and decisions are retained independently from later action attempts.
class OffseasonReadinessReview < ApplicationRecord
  belongs_to :season
  belongs_to :ratings_config_version, optional: true
  belongs_to :reviewer, class_name: 'User'

  validates :fingerprint, :report, presence: true
  before_update :preserve_review

  def self.record!(season, reviewer:, **options)
    OffseasonReadinessLock.new(season).call do
      report = reviewed_report(season, options[:fingerprint])
      decisions = OffseasonReadinessDecisions.new(report, **options.except(:fingerprint)).call
      create!(season:, reviewer:, ratings_config_version_id: report['model_id'], report:, fingerprint: report.fetch('fingerprint'),
              acknowledgement: decisions.fetch(:acknowledgement), deferrals: decisions.fetch(:deferrals))
    end
  end

  def self.reviewed_report(season, fingerprint)
    report = OffseasonReadiness.new(season).call
    verify_fingerprint!(report, fingerprint)
    report
  end

  def self.verify_fingerprint!(report, fingerprint)
    return if fingerprint.present? && report.fetch('fingerprint') == fingerprint

    raise ArgumentError, 'Reviewed evidence is stale or missing its identity. Refresh readiness and save a fresh review.'
  end

  def verify_current
    fresh = OffseasonReadiness.new(season).call
    OffseasonReadinessReview.verify_fingerprint!(fresh, fingerprint)
    problems = OffseasonReadinessReview.required_problems(fresh)
    raise ArgumentError, "Resolve required readiness checks: #{problems.pluck('label').join(', ')}." if problems.any?

    fresh
  end

  private

  public_class_method def self.required_problems(fresh)
    fresh.fetch('checks').select { |check| check['hard'] && check['status'] != 'pass' }
  end

  def preserve_review
    fields = %w[season_id ratings_config_version_id reviewer_id report fingerprint acknowledgement deferrals]
    raise ActiveRecord::ReadOnlyRecord, 'Reviewed evidence is immutable; save a fresh review.' if
      fields.any? { |field| will_save_change_to_attribute?(field) }
  end
end
