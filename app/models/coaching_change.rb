# frozen_string_literal: true

# Manually reviewed coaching facts; confirmation does not imply pace eligibility.
class CoachingChange < ApplicationRecord
  STATUSES = %w[pending confirmed rejected].freeze
  PREVIOUS_ROLES = %w[head_coach assistant interim other].freeze
  FACT_FIELDS = %w[team_id effective_year coach_name destination_school previous_team_id previous_school previous_year
                   previous_role full_season_head_coach previous_season_d1].freeze

  DISCOVERY_FIELDS = %w[discovery_school discovery_coach_name discovery_former_coach discovery_present
                        discovery_team_id discovery_previous_team_id].freeze
  REVIEW_FIELDS = (FACT_FIELDS + DISCOVERY_FIELDS + ['status']).freeze

  belongs_to :team, optional: true
  belongs_to :previous_team, class_name: 'Team', optional: true
  attribute :reconfirm, :boolean, default: false

  scope :confirmed, -> { where(status: 'confirmed') }
  validates :effective_year, numericality: { only_integer: true, in: 1..9999 }
  validates :previous_year, numericality: { only_integer: true, in: 1..9999 }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }
  validates :previous_role, inclusion: { in: PREVIOUS_ROLES }, allow_blank: true
  validates :team, :coach_name, presence: true, if: :confirmed?
  validates :team_id, uniqueness: { scope: :effective_year, conditions: -> { confirmed } }, if: :confirmed?
  validate :coherent_history
  validate :explicit_reconfirmation
  around_save :serialize_changes
  around_destroy :serialize_deletion
  after_save -> { self.reconfirm = false }

  def confirmed?
    status == 'confirmed'
  end

  # Importers may correct pending facts, but only operators can change review decisions.
  def apply_imported_facts(facts)
    validate_import_fields(facts)
    transaction do
      years = import_years(facts)
      CoachingReview.with_year_locks(years) { import_locked_facts(facts, years) }
    end
  end

  private

  def import_locked_facts(facts, years)
    with_lock do
      if years.exclude?(effective_year)
        errors.add(:base, 'Candidate year changed during import; reload and retry the proposal')
        next false
      end
      assign_attributes(facts)
      valid_import? && save
    end
  end

  def import_years(facts)
    target_year = facts.stringify_keys.fetch('effective_year', effective_year)
    [effective_year, self.class.type_for_attribute('effective_year').cast(target_year)]
  end

  def validate_import_fields(facts)
    return if (facts.stringify_keys.keys - FACT_FIELDS).empty?

    raise ArgumentError, 'Import only coaching fact fields; review decisions require manual action'
  end

  def valid_import?
    return true if status == 'pending' || !facts_changed?

    errors.add(:base, 'Imported proposal conflicts with reviewed facts; correct it manually in Rails Admin')
    restore_attributes
    false
  end

  def coherent_history
    errors.add(:previous_year, 'must precede the effective year') if previous_year && effective_year && previous_year >= effective_year
    return unless full_season_head_coach? || previous_season_d1?

    errors.add(:previous_team, 'must be resolved for confirmed previous-season responsibility or D1 coverage') unless previous_team
    errors.add(:previous_year, 'is required for confirmed previous-season responsibility or D1 coverage') unless previous_year
    validate_head_coach_role
  end

  def validate_head_coach_role
    return unless full_season_head_coach? && previous_role != 'head_coach'

    errors.add(:previous_role, 'must be head_coach for full-season responsibility')
  end

  def explicit_reconfirmation
    return unless status_in_database == 'confirmed' && confirmed? && facts_changed? && !reconfirm

    errors.add(:base, 'Coaching facts changed: explicitly reconfirm them or return the record to pending for review')
  end

  def facts_changed?
    FACT_FIELDS.any? { |field| will_save_change_to_attribute?(field) }
  end

  def serialize_changes
    CoachingReview.with_year_locks([effective_year_in_database, effective_year]) do
      validate_current_inputs
      changed_inputs = new_record? || facts_changed? || will_save_change_to_status? || discovery_changed?
      yield
      invalidate_reviews if changed_inputs
    end
  end

  def serialize_deletion
    CoachingReview.with_year_locks([effective_year]) do
      validate_current_inputs
      yield
      CoachingReview.where(year: effective_year).find_each { |review| review.update!(ready: false) }
    end
  end

  def validate_current_inputs
    return if new_record? || current_input_attributes == REVIEW_FIELDS.index_with { |field| attribute_in_database(field) }

    errors.add(:base, 'Coaching facts or decision changed since loading; reload and review the current record before saving')
    raise ActiveRecord::RecordInvalid, self
  end

  def current_input_attributes
    self.class.find_by(id:)&.attributes&.slice(*REVIEW_FIELDS)
  end

  def invalidate_reviews
    years = [effective_year_before_last_save, effective_year].compact
    CoachingReview.where(year: years).find_each { |review| review.update!(ready: false) }
  end

  def discovery_changed?
    discovery_school_in_database.present? && DISCOVERY_FIELDS.any? { |field| will_save_change_to_attribute?(field) }
  end
end
