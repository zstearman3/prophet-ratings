# frozen_string_literal: true

# A frozen policy-specific derivation; source parsing is shared across extraction policies.
class DepartureDatasetNormalization < ApplicationRecord
  # Fresh certificate preparation shares one authenticated header outside mutable AR attributes.
  Reference = Data.define(:id, :header, :source_normalization_ids, :dataset_revision, :summary) do
    def rows
      DepartureDatasetRow.where(departure_dataset_normalization_id: id)
    end
  end

  has_many :rows, class_name: 'DepartureDatasetRow', dependent: :restrict_with_exception

  def readonly?
    persisted? && status_in_database == 'completed'
  end
end
