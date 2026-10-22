# frozen_string_literal: true

# A pinned proposal and its explicit publication decision; never a mutable model configuration.
class PreseasonPublication < ApplicationRecord
  belongs_to :season
  belongs_to :ratings_config_version
  belongs_to :reviewer, class_name: 'User'

  validates :mode, inclusion: { in: %w[initialize revise] }
  validates :status, inclusion: { in: %w[review queued running published failed] }
  validates :fingerprint, :report, presence: true

  def self.select_model(season, model)
    model.settings
    season.with_lock do
      unless season.selected_preseason_model_id == model.id
        season.update!(selected_preseason_model: model, preseason_selection_generation: season.preseason_selection_generation + 1)
      end
    end
  end

  def self.review!(season, reviewer:, mode:)
    season.with_lock do
      model = season.selected_preseason_model || raise(ArgumentError, 'Select a published model first.')
      report = PreseasonPublicationPreview.new(season, ratings_config_version: model, mode:).call
      create!(season:, reviewer:, ratings_config_version: model, mode:, report:, fingerprint: report.fetch('fingerprint'))
    end
  end

  def output_identity
    rows = season.rating_team_seasons
    { fingerprint: current_report.fetch('fingerprint'),
      capture_ids: PreseasonPrior.where(team_season: rows, ratings_config_version:).order(:id).pluck(:id),
      snapshot_ids: season.team_rating_snapshots.where(ratings_config_version:, snapshot_date: season.start_date - 1.day)
                          .order(:id).pluck(:id),
      ranks: rows.order(:overall_rank, :team_id).pluck(:team_id, :overall_rank) }
  end

  def current_report
    PreseasonPublicationPreview.new(season.reload, ratings_config_version:, mode:).call
  end

  def verify_current
    fresh = current_report
    return fresh if fingerprint == fresh.fetch('fingerprint')

    raise ArgumentError, 'Reviewed proposal is stale: model selection, roster or inputs changed. Create and review a fresh preview.'
  end
end
