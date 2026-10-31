# frozen_string_literal: true

module Ingestion
  # Rebuilds a bounded comparison from the retained rejection and current pending game.
  class ScheduleReviewEvidence
    attr_reader :source, :season, :prior, :resolution

    def initialize(source, season)
      @source = source
      @season = season
    end

    def validate
      validate_candidate
      validate_latest
      self
    rescue ObservationResolution::Held, GameObservation::Invalid => error
      raise ArgumentError, "Schedule conflict requires identity review: #{error.message}"
    end

    def incoming = resolution.observation
    delegate :game, to: :resolution

    def participant_correction?
      source.reason.to_s.split(': ').last == 'participant_or_orientation_conflict'
    end

    def fingerprint
      GameScheduleReview.digest(source: source.attributes, prior: prior.attributes, game: game.attributes,
                                sides: TeamGame.where(game:).order(:id).map(&:attributes),
                                identities: GameExternalIdentity.where(game:).order(:id).map(&:attributes),
                                participants: GameScheduleReview.participants_for(resolution),
                                team_identities: team_identity_state, outputs: protected_outputs)
    end

    def schedule_for(choice)
      stored = game.attributes
      options = { 'existing' => stored,
                  'incoming' => stored.merge(ObservationWriter.new(incoming, resolution, game).attributes.stringify_keys) }
      GameScheduleReview.schedule_values(options.fetch(choice))
    end

    def dates
      [incoming.data.fetch(:schedule_date), game.schedule_date.iso8601].uniq.sort
    end

    def self.eligible?(source)
      source.provider == 'cbbd' && source.outcome == 'conflict' &&
        %w[provider_or_profile_conflict participant_or_orientation_conflict].include?(source.reason.to_s.split(': ').last) &&
        source.normalized_payload['source_status'] == 'scheduled'
    end

    private

    def protected_outputs
      NameOnlyScheduleCandidate.output_ids(game)
    end

    def team_identity_state
      payloads = [prior.normalized_payload, incoming.data.as_json]
      keys = payloads.flat_map { |payload| payload.values_at('home', 'away').pluck('external_team_id') }.compact.uniq
      { identities: TeamExternalIdentity.where(provider: 'cbbd', external_id: keys).order(:id).map(&:attributes),
        teams: payloads.map { |payload| resolved_team_ids(payload) } }
    end

    def resolved_team_ids(payload)
      observation = GameObservation.new(payload).validate
      ObservationResolution.new(observation, season).resolve.teams.map { |team| team&.id }
    end

    def validate_candidate
      validate_source
      prepare_candidate
      if participant_correction?
        NameOnlyScheduleCandidate.new(self).validate
      else
        resolution.validate_game(game)
        ScheduleReviewCandidate.new(self).validate
      end
    end

    def prepare_candidate
      observation = GameObservation.new(source.normalized_payload.merge('raw_payload' => source.raw_payload)).validate
      @resolution = ObservationResolution.new(observation, season).resolve
      @prior = ::GameObservation.where(game:, accepted: true).order(id: :desc).first
      validate_game
    end

    def validate_game
      raise ArgumentError, 'No unique existing schedule entry can be reviewed.' unless game
    end

    def validate_source
      raise ArgumentError, 'This rejection cannot be resolved by schedule review.' unless self.class.eligible?(source)
    end

    def validate_latest
      (participant_correction? ? [source] : [source, prior]).each do |original|
        latest = ::GameObservation.where(provider: 'cbbd', external_game_id: original.external_game_id).order(id: :desc).first
        next if GameScheduleReview.payload_fingerprint(latest.normalized_payload) ==
                GameScheduleReview.payload_fingerprint(original.normalized_payload)

        raise ArgumentError, 'Source facts changed; open the latest rejection before reviewing.'
      end
    end
  end
end
