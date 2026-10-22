# frozen_string_literal: true

# Shared writer lock serializes deliveries, including explicit recovery of an interrupted worker.
class PreseasonPublicationExecution
  def initialize(publication)
    @publication = publication
  end

  def call
    Season.with_ratings_lock { execute }
  rescue Season::OperationInProgress => error
    publication.with_lock { fail_publication(error) if publication.status == 'queued' }
  end

  private

  attr_reader :publication

  def execute
    return if publication.reload.status == 'published'

    start
    apply
  rescue StandardError => error
    fail_publication(error)
  end

  def apply
    publication.season.with_lock(requires_new: true) do
      publication.with_lock do
        with_coaching_review { publish }
      end
    end
  end

  def with_coaching_review(&)
    return yield unless publication.ratings_config_version.settings.dig(:preseason, :coaching)

    ProphetRatings::CoachingPaceInputs.new(publication.season).with_review(&)
  end

  def publish
    apply_reviewed(publication.verify_current)
    publication.update!(status: 'published', published_at: Time.current, result: publication.output_identity)
  end

  def apply_reviewed(report)
    mode = publication.mode
    service = PreseasonPublicationPreview.new(publication.season, ratings_config_version: publication.ratings_config_version,
                                                                  mode:).calculation
    mode == 'revise' ? service.call(preview_key: report.fetch('preview_key')) : service.call
  end

  def start
    raise ArgumentError, 'Publication has not been explicitly queued.' unless publication.queued_at

    publication.update!(status: 'running', started_at: Time.current, error_message: nil)
  end

  def fail_publication(error)
    publication.reload.update!(status: 'failed',
                               error_message: "#{error.message} Review the pinned proposal; create a fresh preview if inputs changed.")
  end
end
