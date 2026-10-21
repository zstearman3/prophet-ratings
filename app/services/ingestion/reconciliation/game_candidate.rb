# frozen_string_literal: true

module Ingestion
  module Reconciliation
    # A stable mapping wins; pair/date/venue differences remain explicit review evidence.
    class GameCandidate
      def initialize(season:, external_id:, rows:, teams:, local:)
        @input = { season:, external_id:, rows:, teams:, local: }
        @identity = GameExternalIdentity.find_by(provider: 'cbbd', external_id:)
      end

      def to_h
        { 'external_id' => @input.fetch(:external_id), 'status' => status, 'mapped_id' => @identity&.game_id,
          'superseded' => @identity&.superseded? || false, 'candidate_ids' => games.map(&:id),
          'candidates' => evidence, 'conflicts' => conflicts, 'occurrences' => @input.fetch(:rows).size, 'observation' => observation }
      end

      private

      def observation
        @input.fetch(:rows).first
      end

      def games
        @games ||= if @identity
                     [@identity.game]
                   else
                     @input.fetch(:local).pair_games(team_ids: home_ids + away_ids)
                           .includes(:home_team_game, :away_team_game).select do |game|
                       compatible?(game)
                     end
                   end
      end

      def evidence
        games.map { |game| CandidateEvidence.new(game:, observation: observation, source_pair: [home_ids, away_ids]).to_h }
      end

      def home_ids
        @input.fetch(:teams).fetch(observation.dig('home', 'source_team_id').to_s).fetch('eligible_ids')
      end

      def away_ids
        @input.fetch(:teams).fetch(observation.dig('away', 'source_team_id').to_s).fetch('eligible_ids')
      end

      def compatible?(game)
        return false unless game.season_id == @input.fetch(:season).id

        home, away = LocalEvidence.participants(game)
        (home.intersect?(home_ids) && away.intersect?(away_ids)) || (home.intersect?(away_ids) && away.intersect?(home_ids))
      end

      def conflicts
        source_conflicts + identity_conflicts
      end

      def source_conflicts
        reasons = @input.fetch(:rows).flat_map { |row| row.fetch('conflicts', []) }.uniq + source_identity_conflicts
        unless observation['provider'] == 'cbbd' && observation['season'] == @input.fetch(:season).year &&
               @input.fetch(:teams).values_at(*observation.values_at('home', 'away').pluck('source_team_id').map(&:to_s))
                     .pluck('status').exclude?('conflicting')
          reasons << 'wrong_provider_season_or_participant_evidence'
        end
        reasons
      end

      def source_identity_conflicts
        reasons = @input.fetch(:rows).many? ? ['duplicate_source_identity'] : []
        reasons << 'invalid_source_identity' if @input.fetch(:external_id).blank?
        reasons << 'invalid_schedule_date' unless valid_date?
        reasons
      end

      def valid_date?
        Cbbd::Bounds.date(observation['schedule_date'])
      rescue ArgumentError
        false
      end

      def identity_conflicts
        return [] unless @identity && !compatible?(@identity.game)

        ['stable_identity_participant_or_season_conflict']
      end

      def status
        return 'conflicting' if conflicts.any?
        return 'unmatched' if games.empty?

        resolved_status
      end

      def resolved_status
        return 'ambiguous' if games.many? || evidence.any? { |row| row['alignment'] == 'ambiguous' }
        return 'mapped' if @identity

        evidence.first['rules'].intersect?(%w[non_neutral_orientation_review possible_reschedule]) ? 'review_required' : 'proposed'
      end
    end
  end
end
