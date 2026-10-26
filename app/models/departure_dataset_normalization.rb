# frozen_string_literal: true

# A frozen policy-specific derivation; source parsing is shared across extraction policies.
class DepartureDatasetNormalization < ApplicationRecord
  has_many :rows, class_name: 'DepartureDatasetRow', dependent: :restrict_with_exception

  def readonly?
    persisted? && status_in_database == 'completed'
  end
end
