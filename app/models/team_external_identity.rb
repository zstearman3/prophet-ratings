# frozen_string_literal: true

# Durable provider keys retain their original local team owner.
class TeamExternalIdentity < ApplicationRecord
  # An existing mapping or active authority cannot be reassigned.
  class Conflict < StandardError; end

  belongs_to :team

  validates :provider, :external_id, presence: true
  validate :immutable_identity, if: :persisted?

  def self.associate!(team:, provider:, external_id:)
    identity = create_or_find_by!(provider:, external_id:) { |record| record.team = team }
    raise Conflict, 'External identity already belongs to another team' unless identity.team == team

    identity
  end

  private

  def immutable_identity
    %w[provider external_id team_id].each do |attribute|
      errors.add(attribute, 'cannot be changed') if will_save_change_to_attribute?(attribute)
    end
  end
end
