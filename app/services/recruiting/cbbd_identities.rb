# frozen_string_literal: true

module Recruiting
  # Drafts propose assignments; approval atomically retains the durable CBBD team owners.
  class CbbdIdentities
    def initialize(batch)
      @batch = batch
    end

    def self.find(raw)
      return unless raw.is_a?(Hash) && raw['provider'] == 'cbbd'

      TeamExternalIdentity.find_by(provider: 'cbbd', external_id: raw['provider_team_id'])
    end

    def self.conflict?(raw, team_id)
      saved = find(raw)
      saved && team_id && saved.team_id != team_id
    end

    def state
      scope.order(:id).pluck(:id, :external_id, :team_id)
    end

    def lock
      scope.lock.load
    end

    def associate
      @batch.entries.where(excluded: false).where.not(team_id: nil).find_each(&:associate_external_identity)
    end

    private

    def scope
      TeamExternalIdentity.where(provider: 'cbbd', external_id: @batch.entries.pluck(:provider_team_id))
    end
  end
end
