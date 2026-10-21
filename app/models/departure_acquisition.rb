# frozen_string_literal: true

# One retained acquisition snapshot; terminal attempts cannot be rewritten.
class DepartureAcquisition < ApplicationRecord
  belongs_to :departure_batch
  belongs_to :predecessor, class_name: 'DepartureAcquisition', optional: true
  attr_readonly :plan, :predecessor_id, :departure_batch_id

  validates :status, inclusion: { in: %w[queued running completed incomplete failed] }
  validate :terminal_immutable, on: :update

  before_destroy { throw(:abort) if terminal? }

  def correction_attributes
    attributes.slice('plan', 'manifest', 'dataset', 'evidence', 'status', 'started_at', 'finished_at').merge('predecessor_id' => id)
  end

  def terminal?
    status.in?(%w[completed incomplete failed])
  end

  private

  def terminal_immutable
    errors.add(:base, 'Terminal departure evidence is immutable') if status_in_database.in?(%w[completed incomplete failed]) && changed?
  end
end
