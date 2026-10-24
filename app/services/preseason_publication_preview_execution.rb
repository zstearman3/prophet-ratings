# frozen_string_literal: true

# The season lock protects the pinned selection throughout a read-only calculation.
class PreseasonPublicationPreviewExecution
  def initialize(publication)
    @publication = publication
  end

  def call
    Season.with_ratings_lock { execute }
  rescue Season::OperationInProgress => error
    publication.with_lock { fail_preview(error) if publication.status == 'preview_queued' }
  end

  private

  attr_reader :publication

  def execute
    return unless publication.reload.status.in?(%w[preview_queued preview_running])

    publication.update!(status: 'preview_running', started_at: Time.current, error_message: nil)
    build_review
  rescue StandardError => error
    fail_preview(error)
  end

  def build_review
    season = publication.season
    season.with_lock do
      publication.validate_selection
      report = PreseasonPublicationPreview.new(season, ratings_config_version: publication.ratings_config_version,
                                                       mode: publication.mode).call
      publication.update!(status: 'review', report: PreseasonPublicationPreview.presentation(report),
                          fingerprint: report.fetch('fingerprint'), started_at: nil)
    end
  end

  def fail_preview(error)
    publication.reload.update!(status: 'preview_failed',
                               error_message: "#{error.message} Retry this preview, or create a fresh preview if selection changed.")
  end
end
