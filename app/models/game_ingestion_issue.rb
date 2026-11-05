# frozen_string_literal: true

# Private operational state; source observations and admin decisions remain immutable.
class GameIngestionIssue < ApplicationRecord
  CATEGORIES = %w[scoring participants missing_result source_revision invalid].freeze
  belongs_to :season
  belongs_to :game, optional: true
  belongs_to :original_observation, class_name: 'GameObservation'
  belongs_to :latest_observation, class_name: 'GameObservation'
  belongs_to :retry_acquisition, class_name: 'CbbdReviewRun', optional: true
  has_many :decisions, class_name: 'GameIngestionDecision', dependent: :restrict_with_exception
  validates :provider, :external_game_id, :source_fingerprint, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :state, inclusion: { in: %w[open resolved] }
  scope :unresolved, -> { where(state: 'open') }

  def self.fingerprint(payload)
    GameScheduleReview.digest(fingerprint_fields(payload))
  end

  def self.fingerprint_fields(payload)
    fields = payload.deep_stringify_keys.except('captured_at', 'payload_digest', 'raw_payload')
    fields.each_value { |value| value.delete('field_availability') if value.is_a?(Hash) }
    fields.merge(fields.slice('start_time', 'source_updated_at').transform_values { |value| Ingestion::GameObservation.timestamp(value) })
  end

  def self.capture!(season:, observation:, **options)
    key = { season:, provider: observation.provider, external_game_id: observation.external_game_id, category: options.fetch(:category) }
    candidate = options[:game]
    create_or_find_by!(**key) { |record| record.initialize_source(observation:, game: candidate) }.refresh_source(observation, candidate)
  end

  def initialize_source(attributes)
    observation = attributes.fetch(:observation)
    assign_attributes(original_observation: observation, latest_observation: observation,
                      source_fingerprint: self.class.fingerprint(Ingestion::GameIssueSource.new(observation).payload),
                      game: attributes[:game])
  end

  def refresh_source(observation, candidate)
    with_lock { observe(observation, candidate) }
    self
  end

  def observe(observation, candidate)
    fingerprint = self.class.fingerprint(Ingestion::GameIssueSource.new(observation).payload)
    self.state = 'open' if source_fingerprint != fingerprint
    assign_attributes(latest_observation: observation, source_fingerprint: fingerprint)
    self.game = candidate if candidate
    save!
  end

  def comparison_fingerprint
    GameScheduleReview.digest(source: source_fingerprint, game: game&.attributes,
                              sides: game && TeamGame.where(game:).order(:id).map(&:attributes),
                              identities: game && GameExternalIdentity.where(game:).order(:id).map(&:attributes),
                              participants:)
  end

  def latest_decision
    decisions.where(source_fingerprint:).order(id: :desc).first
  end

  def applied_source_current?
    accepted = GameObservation.where(game:, provider:, external_game_id:, accepted: true).order(id: :desc).first
    return false unless accepted

    original = Ingestion::GameIssueSource.new(accepted).payload
    self.class.fingerprint(original) == source_fingerprint
  end

  def source_payload
    Ingestion::GameIssueSource.new(latest_observation).payload
  end

  def schedule_date
    Date.iso8601(latest_observation.normalized_payload.fetch('schedule_date'))
  end
end
