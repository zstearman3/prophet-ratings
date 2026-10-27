# frozen_string_literal: true

module Departures
  # Validates existing profile evidence before atomically linking every target membership to one revision.
  class ProfilePublication
    LINK_SQL = <<~SQL.squish.freeze
      INSERT INTO team_offseason_profiles (team_season_id, departure_revision_id, created_at, updated_at)
      SELECT id, :revision_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP FROM team_seasons WHERE season_id = :season_id
      ON CONFLICT (team_season_id) DO UPDATE SET departure_revision_id = EXCLUDED.departure_revision_id, updated_at = EXCLUDED.updated_at
    SQL

    def initialize(operation, season)
      @operation = operation
      @season = season
    end

    def validate
      members = @season.team_seasons
      expected = members.order(:team_id).pluck(:team_id)
      Contract.check!(@operation.proposals.order(:team_id).pluck(:team_id) == expected, 'Departure proposal must cover every target team')
      TeamOffseasonProfile.where(team_season_id: members.select(:id)).find_each { |profile| self.class.validate_profile(profile) }
    end

    def link(revision_id)
      query = ApplicationRecord.sanitize_sql_array([LINK_SQL, { revision_id:, season_id: @season.id }])
      ApplicationRecord.connection.execute(query)
    end

    def self.validate_profile(profile)
      ids = { 'recruiting' => profile.recruiting_revision_id, 'departures' => profile.departure_revision_id }
      scalar_evidence(profile)
      membership = profile.team_season
      ids.each { |kind, id| validate_pointer(id, kind, membership) if id }
    end

    def self.validate_pointer(id, kind, membership)
      valid = OffseasonInputRevision.where(id:, season_id: membership.season_id, kind:)
                                    .exists?(["jsonb_exists(payload->'team_inputs', ?)", membership.team_id.to_s])
      Contract.check!(valid, "Reviewed #{kind} revision must cover this team and season")
    end

    def self.scalar_evidence(profile)
      profile.departure_revision_id = nil
      recruiting_id = profile.recruiting_revision_id
      profile.recruiting_revision_id = nil
      profile.validate_revision_evidence
      recruiting_id
    end
  end
end
