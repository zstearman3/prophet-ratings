# frozen_string_literal: true

# A database-backed capture and review draft; publication points to immutable input evidence.
class RecruitingBatch < ApplicationRecord
  belongs_to :season
  belongs_to :revision, class_name: 'OffseasonInputRevision', optional: true
  has_many :entries, class_name: 'RecruitingEntry', dependent: :destroy

  validates :status, inclusion: { in: %w[queued fetching ready failed published] }
  validate :source_year_matches_target

  def self.listing(season_id)
    seasons = Season.order(year: :desc).select(:id, :year)
    season = season_id.present? ? seasons.find(season_id) : seasons.first
    { seasons:, season:, batches: season ? recent_summaries(season) : [] }
  end

  def self.recent_summaries(season)
    where(season:).select(:id, :season_id, :status, :page_count, :created_at).order(id: :desc).limit(20)
  end

  def source_url
    Recruiting::HtmlPage.source_url(source_year)
  end

  def dataset
    value = Recruiting::Dataset.new(extract_bytes, snapshot_bytes)
    unless value.manifest.fetch('dataset_revision') == dataset_revision
      raise ArgumentError,
            'Stored recruiting evidence changed; fetch a new batch.'
    end

    value
  end

  def require_draft
    raise ArgumentError, 'Only a ready, unpublished recruiting batch can be edited or approved.' unless status == 'ready'
  end

  private

  def source_year_matches_target
    return if season && source_year == season.year - 1 && Recruiting::Extract.valid_year?(source_year)

    errors.add(:source_year, 'must be the recruiting year immediately before the target season')
  end
end
