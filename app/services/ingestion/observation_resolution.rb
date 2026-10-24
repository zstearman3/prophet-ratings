# frozen_string_literal: true

module Ingestion
  # Resolve supplied IDs before labels; labels are only conservative bootstrap candidates.
  class ObservationResolution
    # Expected audit-only outcomes never authorize partial domain writes.
    class Held < StandardError
      attr_reader :outcome, :participants

      def initialize(outcome, reason, participants: [])
        @outcome = outcome
        @participants = participants
        super(reason)
      end
    end

    attr_reader :observation, :season, :teams, :memberships

    def initialize(observation, season)
      @observation = observation
      @season = season
    end

    def resolve
      validate_context
      resolve_participants
      validate_memberships
      self
    end

    def untracked?
      memberships.any?(&:nil?)
    end

    def game
      source_identity&.game || ObservationGameLookup.new(self).call
    end

    def source_identity
      external_id = data[:external_game_id]
      return if external_id.blank?

      GameExternalIdentity.find_by(provider: data[:provider], external_id:)
    end

    def lock_keys
      ["game-bootstrap:#{season.id}:#{data[:schedule_date]}:#{teams.compact.map(&:id).sort.join(':')}",
       "game-source:#{data[:provider]}:#{data[:external_game_id]}"]
    end

    def lock
      lock_keys.each { |key| self.class.transaction_lock(key) }
    end

    def self.transaction_lock(key)
      connection = Game.connection
      connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{connection.quote(key)}, 0))")
    end

    def incoming_names
      GameObservation::SIDES.map { |label| data[label][:name] }
    end

    def validate_game(game)
      hold('conflict', 'game_season_conflict') unless game.season_id == season.id
      hold('superseded', 'superseded_game_identity') if source_identity&.reload&.superseded?
      GameObservation::SIDES.each_with_index do |label, index|
        ObservationParticipantIdentity.new(self, game, label).validate
        self.class.validate_side(game, label, teams[index]&.id)
      end
    end

    def self.validate_side(game, label, team_id)
      current = game.public_send("#{label}_team_game")
      return validate_stored_name(game.public_send("#{label}_team_name"), team_id) unless current

      raise Held.new('conflict', 'participant_or_orientation_conflict') if current.team_id != team_id
    end

    def self.validate_stored_name(name, team_id)
      candidates = Team.matching_school_or_alias(name).to_a
      raise Held.new('ambiguous', 'ambiguous_stored_participant', participants: [name]) if candidates.size > 1
      return if candidates.empty? || candidates.map(&:id).include?(team_id)

      raise Held.new('conflict', 'participant_or_orientation_conflict')
    end

    def self.unique_team(candidates, name)
      raise Held.new('ambiguous', 'ambiguous_participant', participants: [name]) if candidates.size > 1
      raise Held.new('unmatched', 'unmatched_participant', participants: [name]) if candidates.empty?

      candidates.first
    end

    private

    def data = observation.data

    def validate_context
      date = Date.iso8601(data[:schedule_date])
      valid = season && season.year == data[:season_year] && (season.start_date..season.end_date).cover?(date)
      hold('unmatched', 'invalid_season_context') unless valid
      hold('unmatched', 'missing_stable_game_identity') unless data[:external_game_id] || observation.schedule_projection?
    end

    def resolve_participants
      @teams = GameObservation::SIDES.map { |label| ObservationTeamResolution.new(self, data.fetch(label)).call }
      hold('conflict', 'participants_must_differ') if teams.first == teams.last
      @memberships = teams.map { |team| TeamSeason.find_by(team:, season:) if team }
    end

    def validate_memberships
      return if memberships.all? || (data[:provider] == 'cbbd' && memberships.any?)

      hold('unmatched', 'missing_team_season')
    end

    def hold(outcome, reason)
      raise Held.new(outcome, reason)
    end
  end
end
