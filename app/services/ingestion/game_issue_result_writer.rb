# frozen_string_literal: true

module Ingestion
  # Write one explicitly reviewed result; ordinary ingestion freshness policy stays unchanged.
  class GameIssueResultWriter
    def initialize(issue:, action:, values:)
      @issue = issue
      @action = action
      @values = values
      @context = {}
    end

    def call
      Game.transaction(requires_new: true) { write_reviewed_result }
    rescue GameIssuePayload::IncompleteSource
      raise unless @action == 'select_participants'

      record_unavailable_result
      false
    end

    private

    def write_reviewed_result
      prepare_context
      validate_candidate
      save_exception
      remove_untracked_sides
      write_result
    end

    def record_unavailable_result
      payload = @issue.source_payload.merge('raw_payload' => @issue.latest_observation.raw_payload)
      report = ObservationAudit.new(GameObservation.new(payload), nil).retain('incomplete', 'missing_required_box_data')
      GameIssueRecorder.new(season: @issue.season, report: report.merge(final_box: 'missing')).call
    end

    def prepare_context
      payload = GameIssuePayload.new(@issue, @action, @values).call
      @context[:observation] = GameObservation.new(payload).validate
      @context[:resolution] = ObservationResolution.new(@context.fetch(:observation), @issue.season).resolve
      validate_completion
      @context.fetch(:resolution).lock
    end

    def observation
      @context.fetch(:observation)
    end

    def validate_completion
      strict = observation.strict_final?
      observation.validate_duration if strict
      complete = observation.final? && (strict || @context.fetch(:resolution).untracked?)
      raise GameIssuePayload::IncompleteSource, 'A complete confirmed final result is required.' unless complete
    end

    def validate_candidate
      resolution = @context.fetch(:resolution)
      @context[:game] = resolution.game
      validate_owner
      @context.fetch(:game).lock!
      validate_selected_participants
    end

    def validate_selected_participants
      @context.fetch(:resolution).validate_game(@context.fetch(:game)) unless @action == 'select_participants'
    end

    def validate_owner
      resolution = @context.fetch(:resolution)
      candidate = @context.fetch(:game)
      raise ArgumentError, 'No unique game exists; review source identity first.' unless candidate && candidate == @issue.game
      raise ArgumentError, 'This source identity has been superseded.' if resolution.source_identity&.superseded?
      raise ArgumentError, 'Game belongs to a different season.' unless candidate.season_id == @issue.season_id
    end

    def save_exception
      @issue.update!(effective_payload: @context.fetch(:observation).data.except(:raw_payload).as_json,
                     participants: GameScoringReview.participants_for(@context.fetch(:resolution)), game: @context.fetch(:game))
    end

    def remove_untracked_sides
      game = @context.fetch(:game)
      %i[home away].each_with_index do |label, index|
        next if @context.fetch(:resolution).memberships[index]

        game.public_send("#{label}_team_game")&.destroy!
        game.association("#{label}_team_game").reset
      end
    end

    def write_result
      observation = @context.fetch(:observation)
      game = @context.fetch(:game)
      ObservationWriter.new(observation, @context.fetch(:resolution), game, scoring_exception: ScoringException.new(@issue)).call
      retain_provenance
      game
    end

    def retain_provenance
      data = observation.data
      game = @context.fetch(:game)
      GameExternalIdentity.associate!(game:, provider: data[:provider], external_id: data[:external_game_id])
      report = ObservationAudit.new(observation, game).retain('final', 'admin_reviewed_ingestion', accepted: true)
      GameIssueRecorder.new(season: @issue.season, report:).call
    end
  end
end
