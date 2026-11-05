# frozen_string_literal: true

module Ingestion
  # Construct only explicitly selected values; never mutate the retained source evidence.
  class GameIssuePayload
    # A valid participant choice can be recorded while incomplete source results remain held.
    class IncompleteSource < ArgumentError; end

    def initialize(issue, action, values)
      @issue = issue
      @action = action
      @values = values
    end

    def call
      return scoring_payload if @action == 'select_scores'

      GameObservation.new(selected_source).validate.data
    end

    def self.apply_reported_points(payload)
      %w[home away].each do |label|
        side = payload.fetch(label)
        side.fetch('stats')['points'] = side.fetch('score')
      end
    end

    private

    def selected_source
      payload = source_payload
      select_participants(payload) if @action == 'select_participants'
      validate_source
      self.class.apply_reported_points(payload)
      payload
    end

    def source_payload
      @issue.source_payload.deep_dup.merge('raw_payload' => @issue.latest_observation.raw_payload)
    end

    def scoring_payload
      raise ArgumentError, 'This issue is not a scoring discrepancy.' unless @issue.category == 'scoring'

      ScoringReviewEvidence.new(@issue.latest_observation, @issue.season).validate.selected_payload(@values)
    end

    def validate_source
      row = @issue.latest_observation.raw_payload
      reasons = Cbbd::ImportValidation.new(row).reasons
      return if reasons.empty? || ScoringReviewEvidence.reviewable?(row, @issue.season)

      raise IncompleteSource, 'Source result is incomplete or invalid; retry after source correction.'
    end

    def select_participants(payload)
      raise ArgumentError, 'Choose both participants.' unless @values.keys.sort == %w[away home]

      %w[home away].each { |label| select_side(payload.fetch(label), @values.fetch(label)) }
    end

    def select_side(side, choice)
      return validate_untracked(side) if choice == 'source'

      membership = @issue.season.team_seasons.find_by(team_id: Integer(choice, 10, exception: false))
      raise ArgumentError, 'Choose a team with membership in this season.' unless membership

      side.merge!('name' => membership.team.school, 'external_team_id' => nil)
    end

    def validate_untracked(side)
      team = resolved_team(side)
      return unless team && @issue.season.team_seasons.exists?(team:)

      raise ArgumentError, 'This source participant is a tracked team; select its team entry.'
    end

    def resolved_team(side)
      observation = GameObservation.new(@issue.source_payload).validate
      context = ObservationResolution.new(observation, @issue.season)
      ObservationTeamResolution.new(context, side.deep_symbolize_keys).call
    end
  end
end
