# frozen_string_literal: true

# Ordered annual evidence, loaded one team at a time during acquisition.
class DepartureDatasetRow < ApplicationRecord
  belongs_to :departure_dataset_normalization

  def readonly?
    persisted?
  end
end
