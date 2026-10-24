# frozen_string_literal: true

# Scheduling checks the saved review; the worker revalidates all evidence before writing.
class PreseasonPublicationQueue
  def initialize(publication, actor:, fingerprint:, acknowledge:)
    @publication = publication
    @actor = actor
    @fingerprint = fingerprint
    @acknowledge = acknowledge
  end

  def call
    enqueue if Season.with_ratings_lock { prepare_queue }
    PreseasonPublicationPage.summary(PreseasonPublication.all).find(publication.id)
  end

  private

  def prepare_queue
    publication.season.with_lock do
      with_publication_lock { prepare_transition }
    end
  end

  def with_publication_lock
    PreseasonPublication.transaction do
      @publication = PreseasonPublicationPage.summary(PreseasonPublication.all).lock.find(publication.id)
      yield
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
    already_queued = publication.queued_at
    validate_acknowledgement unless already_queued
    publication.update!(status: 'queued', queued_at: Time.current, error_message: nil,
                        acknowledgement: already_queued ? publication.acknowledgement : acknowledgement)
  end

  attr_reader :publication, :actor, :fingerprint, :acknowledge

  def validate_identity
    raise ArgumentError, 'Preview identity is missing or differs; reload this review.' unless fingerprint == publication.fingerprint

    unless publication.status.in?(%w[review queued running failed])
      raise ArgumentError, 'The preview must finish successfully before publication.'
    end

    publication.validate_selection
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
    with_publication_lock do
      if publication.status == 'queued'
        publication.update!(status: 'failed',
                            error_message: "Could not enqueue publication: #{error.message}. Retry this review after checking the worker.")
      end
    end
  end
end
