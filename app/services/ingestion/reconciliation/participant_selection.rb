# frozen_string_literal: true

module Ingestion
  module Reconciliation
    # The selected stable team map must support the chosen local game and memberships.
    class ParticipantSelection
      def initialize(game:, source:, season_id:)
        @game = game
        @source = source
        @season_id = season_id
      end

      def validate
        raise ArgumentError, 'Explicit stable participant mappings required' if @source.any?(nil) || @source.uniq.size != 2
        raise ArgumentError, 'Selected team and game participants disagree' unless participant_pairs.include?(@source)
        raise ArgumentError, 'Local game season differs' unless @game.season_id == @season_id

        validate_memberships
      end

      def self.valid_membership?(row, season)
        row.team_season.attributes.slice('team_id', 'season_id') == { 'team_id' => row.team_id, 'season_id' => season.id }
      end

      private

      def participant_pairs
        home, away = LocalEvidence.participants(@game)
        home.product(away) + away.product(home)
      end

      def local_memberships_valid?
        TeamGame.where(game: @game).includes(:team_season).all? { |row| ParticipantSelection.valid_membership?(row, @game.season) }
      end

      def validate_memberships
        memberships = TeamSeason.where(season_id: @season_id, team_id: @source).pluck(:team_id)
        raise ArgumentError, 'Missing target-season participant membership' unless memberships.sort == @source.sort

        return if local_memberships_valid?

        raise ArgumentError, 'Inconsistent local participant membership'
      end
    end
  end
end
