# frozen_string_literal: true

# The exact displayed proposal is checked again before scheduling a pinned operation.
class PreseasonPublicationQueue
  def initialize(publication, actor:, fingerprint:, acknowledge:)
    @publication = publication
    @actor = actor
    @fingerprint = fingerprint
    @acknowledge = acknowledge
  end

  def call
    Season.with_ratings_lock { queue }
    publication.reload
  end

  private

  def queue
    enqueue if prepare_queue
  end

  def prepare_queue
    publication.season.with_lock do
      publication.with_lock { prepare_transition }
    end
  end

  def prepare_transition
    status = publication.status
    return if status == 'published'

    validate_identity
    record_queue unless status == 'queued'
    publication
  end

  def record_queue
    validate_acknowledgement
    publication.update!(status: 'queued', queued_at: Time.current, error_message: nil,
                        acknowledgement: acknowledgement)
  end

  attr_reader :publication, :actor, :fingerprint, :acknowledge

  def validate_identity
    raise ArgumentError, 'Preview identity is missing or differs; reload this review.' unless fingerprint == publication.fingerprint

    publication.verify_current
  end

  def validate_acknowledgement
    return if publication.report.fetch('gaps').empty? || ActiveModel::Type::Boolean.new.cast(acknowledge)

    raise ArgumentError, 'Explicitly acknowledge the displayed missing evidence before publication.'
  end

  def acknowledgement
    gaps = publication.report.fetch('gaps')
    return {} if gaps.empty?

    { admin_id: actor.id, acknowledged_at: Time.current.iso8601(6), fingerprint: publication.fingerprint,
      season_id: publication.season_id, model_id: publication.ratings_config_version_id, mode: publication.mode,
      gaps: }
  end

  def enqueue
    return if PublishPreseasonJob.perform_later(publication.id)

    raise ActiveJob::EnqueueError, 'The worker job was not enqueued.'
  rescue StandardError => error
    publication.with_lock do
      if publication.status == 'queued'
        publication.update!(status: 'failed',
                            error_message: "Could not enqueue publication: #{error.message}. Retry this review after checking the worker.")
      end
    end
  end
end
