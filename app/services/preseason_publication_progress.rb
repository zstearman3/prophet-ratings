# frozen_string_literal: true

# Only persisted workflow evidence certifies a selected model's publication.
class PreseasonPublicationProgress
  def initialize(season)
    @season = season
    @model = season.selected_preseason_model
    @publication = season.preseason_publications.where(ratings_config_version: @model).order(id: :desc).first if @model
  end

  def call
    OffseasonSetupProgress::Step.new(key: 'preseason', label: 'Preview and publish preseason ratings', status: current_status,
                                     last_result: summary,
                                     next_action: 'Select a published model, review a fresh preview and publish unchanged inputs.')
  end

  private

  attr_reader :season, :model, :publication

  def current_status
    return 'needs_review' unless publication
    return 'needs_review' unless publication.report['selection_generation'] == season.preseason_selection_generation

    status = publication.status
    status == 'published' ? published_status : status
  end

  def published_status
    publication.result['fingerprint'] == publication.current_report['fingerprint'] ? 'complete' : 'needs_review'
  rescue ArgumentError, ActiveRecord::RecordInvalid
    'needs_review'
  end

  def summary
    return 'No model selected; existing legacy outputs are unverified by this workflow.' unless model

    "Selected model #{model.name} (##{model.id}); latest retained review: #{publication&.id || 'none'} " \
      "(#{publication&.status || 'unreviewed'}). Existing input approvals are retained independently."
  end
end
