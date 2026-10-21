# frozen_string_literal: true

# Durable provider keys retain their original local game owner.
class GameExternalIdentity < ApplicationRecord
  # An existing mapping or active authority cannot be reassigned.
  class Conflict < StandardError; end

  belongs_to :game

  validates :provider, :external_id, presence: true
  validate :immutable_identity, if: :persisted?
  validate :reviewed_supersession_only, if: :persisted?

  scope :active, -> { where(superseded_at: nil) }

  def self.associate!(game:, provider:, external_id:)
    identity = create_or_find_by!(provider:, external_id:) { |record| record.game = game }
    raise Conflict, 'External identity already belongs to another game' unless identity.game == game

    identity
  rescue ActiveRecord::RecordNotFound
    raise Conflict, 'Provider already has an active identity for this game'
  end

  def superseded?
    superseded_at.present?
  end

  def supersede!(external_id:)
    game.with_lock(requires_new: true) do
      reload
      next self if !superseded? && self.external_id == external_id
      next current_replacement(external_id) if superseded?

      replace_active_source(external_id)
    end
  end

  # Validation and authority conflicts are expected outcomes of a review attempt.
  def supersede(external_id:)
    supersede!(external_id:)
  rescue Conflict, ActiveRecord::RecordInvalid
    false
  end

  private

  def replace_active_source(external_id)
    self.superseded_at = Time.current
    save!(context: :reviewed_supersession)
    replacement = self.class.associate!(game:, provider:, external_id:)
    raise Conflict, 'A superseded identity cannot be reactivated' if replacement.superseded?

    replacement
  end

  def current_replacement(external_id)
    self.class.active.find_by(game_id:, provider:, external_id:) ||
      raise(Conflict, 'This identity has already been superseded by a different source')
  end

  def reviewed_supersession_only
    return unless will_save_change_to_superseded_at?
    return if validation_context == :reviewed_supersession && superseded_at_in_database.blank? && superseded_at.present?

    errors.add(:superseded_at, 'can only be changed by reviewed replacement')
  end

  def immutable_identity
    %w[provider external_id game_id].each do |attribute|
      errors.add(attribute, 'cannot be changed') if will_save_change_to_attribute?(attribute)
    end
  end
end
