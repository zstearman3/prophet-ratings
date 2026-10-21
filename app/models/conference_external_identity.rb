# frozen_string_literal: true

# Durable provider keys retain their original local conference owner.
class ConferenceExternalIdentity < ApplicationRecord
  # An existing mapping or active authority cannot be reassigned.
  class Conflict < StandardError; end

  belongs_to :conference

  validates :provider, :external_id, presence: true
  validate :immutable_identity, if: :persisted?

  def self.associate!(conference:, provider:, external_id:)
    identity = create_or_find_by!(provider:, external_id:) { |record| record.conference = conference }
    raise Conflict, 'External identity already belongs to another conference' unless identity.conference == conference

    identity
  end

  private

  def immutable_identity
    %w[provider external_id conference_id].each do |attribute|
      errors.add(attribute, 'cannot be changed') if will_save_change_to_attribute?(attribute)
    end
  end
end
