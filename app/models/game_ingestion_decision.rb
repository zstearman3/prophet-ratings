# frozen_string_literal: true

# Immutable private record of an admin's exact source/game decision.
class GameIngestionDecision < ApplicationRecord
  belongs_to :game_ingestion_issue
  belongs_to :actor, class_name: 'User'
  validates :action, inclusion: { in: %w[acknowledge select_scores select_participants accept_source] }
  validates :source_fingerprint, :comparison_fingerprint, presence: true
  validate :admin_actor
  before_validation :record_message
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Ingestion decisions are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Ingestion decisions are immutable' }

  private

  def admin_actor
    errors.add(:actor, 'must be an admin') unless actor&.admin?
  end

  def record_message
    self.message = action == 'acknowledge' ? 'Acknowledged by admin' : 'Approved by admin'
  end
end
