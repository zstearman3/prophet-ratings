# frozen_string_literal: true

# Partial source rows cannot be used as evidence of complete coverage.
class DepartureSourceNormalization < ApplicationRecord
  # Only scalar normalization metadata remains live while processing the next source.
  Reference = Data.define(:id, :status, :rows_digest, :row_count, :failure) do
    def rows
      DepartureNormalizedRow.where(departure_source_normalization_id: id)
    end
  end

  belongs_to :departure_source_capture
  has_many :rows, class_name: 'DepartureNormalizedRow', dependent: :restrict_with_exception

  def readonly?
    persisted? && status_in_database == 'completed'
  end
end
