# frozen_string_literal: true

# A durable worker result; its signature authenticates the exact reviewed projection.
class DepartureValidation < ApplicationRecord
  belongs_to :departure_batch
  belongs_to :departure_acquisition
  belongs_to :departure_dataset_normalization, optional: true
  belongs_to :offseason_input_revision, optional: true
  has_many :proposals, class_name: 'DepartureProposal', dependent: :restrict_with_exception
  has_one :approval, class_name: 'DepartureApproval', dependent: :restrict_with_exception

  def current?
    Departures::ValidationIntegrity.new(self).current?
  end
end
