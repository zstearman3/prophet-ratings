# frozen_string_literal: true

# Private PostgreSQL evidence; no public attachment or transient filesystem dependency.
class CbbdReviewRun < ApplicationRecord
  belongs_to :season
  belongs_to :active_comparison, class_name: 'CbbdReviewComparison', optional: true
  has_many :captures, class_name: 'CbbdReviewCapture', dependent: :restrict_with_exception
  has_many :comparisons, class_name: 'CbbdReviewComparison', dependent: :restrict_with_exception

  validates :status, inclusion: { in: %w[queued running completed failed] }
  validates :maximum_requests, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 10_000 }
  validates :retries, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }
  validate :valid_bounds
  before_create :initialize_manifest
  before_update :preserve_evidence

  def self.listing(season_id)
    seasons = Season.order(year: :desc).select(:id, :year)
    season = season_id.present? ? seasons.find(season_id) : seasons.first
    { seasons:, season:, runs: season ? recent_summaries(season) : [] }
  end

  def self.recent_summaries(season)
    where(season:).select(:id, :status, :start_date, :end_date, :created_at).order(id: :desc).limit(30)
  end

  def comparison_job
    GoodJob::Job.labeled("cbbd-comparison:#{id}").where(job_class: 'CompareCbbdReviewJob')
                .select(:id, :created_at, :performed_at, :finished_at, Arel.sql('(error IS NOT NULL) AS failed'))
                .order(created_at: :desc).first
  end

  def comparison_summaries
    comparisons.select(:version, :identity_mapping_decision_id).order(version: :desc)
  end

  def review_comparison(version)
    version.present? ? comparisons.find_by!(version:) : active_comparison
  end

  def bounds
    Ingestion::Cbbd::Bounds.new(season: season.year, start_date: start_date.to_s, end_date: end_date.to_s).to_h
  end

  def verified_replay
    verify_evidence
    store = Ingestion::Cbbd::DatabaseCaptureStore.new(self)
    manifest.fetch('acquisition').fetch('captures').each { |reference| store.read(reference) }
    normalized_replay.deep_dup
  end

  def evidence_hash
    SeasonMembershipProposal.digest([manifest, normalized_replay])
  end

  private

  def initialize_manifest
    return unless manifest.empty?

    ledger = { 'complete' => false, 'captures' => [], 'attempts' => 0, 'selected_captures' => [],
               'failures' => [], 'partitions' => [], 'decisions' => [], 'coverage' => 'unknown' }
    self.manifest = { 'bounds' => bounds, 'maximum_requests' => maximum_requests, 'retries' => retries,
                      'finalized' => false, 'acquisition' => ledger }
  end

  def verify_evidence
    raise ArgumentError, 'Acquisition is not finalized with normalized evidence' unless manifest['finalized'] && normalized_replay
    raise Ingestion::Cbbd::CaptureStore::IntegrityError, 'Stored evidence changed' unless evidence_digest == evidence_hash
  end

  def preserve_evidence
    return unless evidence_digest_in_database
    return unless %w[manifest normalized_replay evidence_digest].any? { |field| will_save_change_to_attribute?(field) }

    raise ActiveRecord::ReadOnlyRecord, 'Finalized CBBD evidence is immutable'
  end

  def valid_bounds
    return unless season

    Ingestion::Cbbd::Bounds.new(season: season.year, start_date: start_date_before_type_cast.to_s, end_date: end_date_before_type_cast.to_s)
  rescue ArgumentError => error
    errors.add(:base, error.message)
  end
end
