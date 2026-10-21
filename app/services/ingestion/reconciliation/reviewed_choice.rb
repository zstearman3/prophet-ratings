# frozen_string_literal: true

module Ingestion
  module Reconciliation
    # One explicit candidate choice; validates immutable ownership and active authority.
    class ReviewedChoice
      def initialize(choice:, comparison:, teams:)
        @choice = choice
        @comparison = comparison
        @teams = teams
      end

      def validate
        validate_shape
        raise ArgumentError, 'Unreviewable source evidence' if candidate['status'] == 'conflicting'
        raise ArgumentError, 'Target is not a reviewed candidate' unless candidate['candidate_ids'].include?(local_id)

        team? ? validate_team : validate_game
      end

      def apply
        identity = team? ? TeamExternalIdentity.associate!(team: Team.find(local_id), provider: 'cbbd', external_id:) : apply_game
        @choice.merge('identity_id' => identity.id)
      end

      private

      def team?
        @choice['entity'] == 'team'
      end

      def external_id
        @choice['external_id']
      end

      def local_id
        @choice['local_id']
      end

      def validate_shape
        raise ArgumentError, 'Unknown choice keys' if (@choice.keys - %w[entity external_id local_id action supersedes_external_id]).any?
        raise ArgumentError, 'Invalid entity/action' unless %w[team game].include?(@choice['entity']) &&
                                                            %w[associate supersede].include?(@choice['action'])
        raise ArgumentError, 'Opaque source ID and integer target required' unless external_id.is_a?(String) && local_id.is_a?(Integer)
      end

      def candidate
        @candidate ||= @comparison.fetch("#{@choice['entity']}s").find { |row| row['external_id'] == external_id } ||
                       raise(ArgumentError, 'Unknown source identity')
      end

      def validate_team
        raise ArgumentError, 'Teams cannot supersede' unless @choice['action'] == 'associate' && !@choice.key?('supersedes_external_id')
        raise ArgumentError, 'Missing target-season membership' unless candidate['eligible_ids'].include?(local_id)

        identity = TeamExternalIdentity.find_by(provider: 'cbbd', external_id:)
        raise ArgumentError, 'Existing source cannot change team' if identity && identity.team_id != local_id
      end

      def game
        @game ||= Game.find(local_id)
      end

      def active_identity
        GameExternalIdentity.active.find_by(provider: 'cbbd', game:)
      end

      def validate_game
        identity = GameExternalIdentity.find_by(provider: 'cbbd', external_id:)
        raise ArgumentError, 'Existing source cannot change game or reactivate' if identity &&
                                                                                   (identity.game != game || identity.superseded?)

        validate_authority
        validate_participants
      end

      def validate_authority
        identity = GameExternalIdentity.find_by(provider: 'cbbd', external_id:)
        if @choice['action'] == 'supersede'
          previous = active_identity&.external_id
          unless previous && previous == @choice['supersedes_external_id'] && previous != external_id
            raise ArgumentError, 'Replacement must name the active same-game identity'
          end
        elsif @choice.key?('supersedes_external_id') || (active_identity && active_identity != identity)
          raise ArgumentError, 'Active authority requires explicit supersession'
        end
      end

      def validate_participants
        source = %w[home away].map { |side| @teams[candidate.dig('observation', side, 'source_team_id').to_s] }
        ParticipantSelection.new(game:, source:, season_id: @comparison.fetch('season_id')).validate
      end

      def apply_game
        return active_identity.supersede!(external_id:) if @choice['action'] == 'supersede'

        GameExternalIdentity.associate!(game:, provider: 'cbbd', external_id:)
      end
    end
  end
end
