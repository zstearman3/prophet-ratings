# frozen_string_literal: true

# Annual raw/reviewed evidence is append-only; profile pointers select current inputs.
class OffseasonInputRevision < ApplicationRecord
  belongs_to :season
  belongs_to :predecessor, class_name: 'OffseasonInputRevision', optional: true

  validates :kind, inclusion: { in: %w[recruiting departures] }
  validates :version, :reason, :payload, presence: true
  validates :input_hash, :dataset_hash, :review_hash, format: { with: /\A[a-f0-9]{64}\z/ }
  validates :input_hash, :version, uniqueness: { scope: %i[season_id kind] }
  validate :validate_identity

  def readonly?
    persisted?
  end

  def team_input(team_id)
    payload.fetch('team_inputs').fetch(team_id.to_s)
  end

  def self.recruiting_approved?(reviewed)
    reviewed['review_status'] == 'reviewed' && reviewed.dig('approval', 'approved_by').present? &&
      reviewed.dig('approval', 'approved_at').present?
  end

  def self.departures_approved?(reviewed)
    reviewed['decision'] == 'approved' && reviewed['reviewed_by'].present? && reviewed['reviewed_at'].present?
  end

  private

  def approved?
    reviewer = self.class
    predicates = { 'recruiting' => reviewer.method(:recruiting_approved?), 'departures' => reviewer.method(:departures_approved?) }
    predicates[kind]&.call(payload.fetch('review', {}))
  end

  def validate_payload_contract
    errors.add(:kind, 'does not match retained evidence') unless payload['kind'] == kind
    errors.add(:dataset_hash, 'does not match retained evidence') unless payload['dataset_hash'] == dataset_hash
    unless payload['review_hash'] == review_hash && Departures::Contract.digest(payload['review']) == review_hash
      errors.add(:review_hash, 'does not match retained approval')
    end
    errors.add(:payload, 'requires reviewed approval') unless approved?
  end

  def validate_identity
    return if payload.blank?

    errors.add(:input_hash, 'does not match retained evidence') unless input_hash == Departures::Contract.digest(payload)
    validate_payload_contract
    validate_predecessor
  end

  def validate_predecessor
    return unless predecessor
    return if predecessor.season_id == season_id && predecessor.kind == kind

    errors.add(:predecessor, 'must belong to the same season and input kind')
  end
end
