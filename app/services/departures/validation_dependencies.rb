# frozen_string_literal: true

module Departures
  # Compact live domain identities; no annual source or payload is loaded for currentness.
  class ValidationDependencies
    PLAN_SQL = "encode(sha256(convert_to((plan - 'sources' - 'captures')::text, 'UTF8')), 'hex')"

    def initialize(batch_id)
      @batch = DepartureBatch.select(DepartureBatch.column_names - ['plan']).find(batch_id)
    end

    def digest
      Contract.digest([batch_state, self.class.mapping_state, roster_state, profile_state, revision_state])
    end

    private

    def batch_state
      id = @batch.id
      [@batch.attributes, DepartureBatch.where(id:).pick(Arel.sql(PLAN_SQL)),
       @batch.acquisitions.order(id: :desc).pick(:id, :status),
       DepartureValidation.where(departure_batch_id: id).maximum(:id)]
    end

    public_class_method def self.mapping_state
      [Team.order(:id).pluck(:id, :school), TeamAlias.order(:id).map(&:attributes),
       TeamExternalIdentity.order(:id).map(&:attributes)]
    end

    def memberships
      year = @batch.season.year
      TeamSeason.joins(:season).where(seasons: { year: [year - 1, year] }).order(:id)
    end

    def roster_state
      [Season.where(id: @batch.season_id).pluck(:id, :year), memberships.pluck(:id, :team_id, :season_id)]
    end

    def profile_state
      TeamOffseasonProfile.where(team_season_id: memberships.select(:id)).order(:id).map(&:attributes)
    end

    def revision_state
      OffseasonInputRevision.where(season_id: @batch.season_id, kind: 'departures').maximum(:id)
    end
  end
end
