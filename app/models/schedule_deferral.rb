# frozen_string_literal: true

# Append-only operator readiness decision, separate from acquisition and model approval.
class ScheduleDeferral < ApplicationRecord
  belongs_to :season
  belongs_to :requested_by, class_name: 'User'
  validates :reason, presence: true, length: { maximum: 2000 }
  validate :no_usable_schedule, on: :create

  def summary
    "Deferred by #{requested_by.email} at #{created_at}: #{reason}."
  end

  def readonly?
    persisted?
  end

  private

  def no_usable_schedule
    return unless season && ScheduleReadiness.new(season).usable?

    errors.add(:base, 'A usable schedule is stored; review and reassess readiness instead of deferring acquisition.')
  end
end
