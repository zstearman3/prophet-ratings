# frozen_string_literal: true

module ProphetRatings
  # Builds the shared, versioned presentation row for preseason reports.
  class PreseasonReportBuilder
    def initialize(row, inputs, config, prior:)
      @row = row
      @inputs = inputs
      @prior = prior
      @formula = PreseasonPriorFormula.new(inputs, config)
    end

    def call
      {
        team_id: @row.team_id, team_season_id: @row.id, added: @prior.blank?,
        profile_before: @prior&.inputs&.fetch('profile', nil), profile_after: @inputs['profile'],
        outputs_before: @prior&.outputs, outputs_after: @formula.call,
        coaching: @formula.pace_report, efficiency: @formula.efficiency_report, inputs: @inputs
      }
    end
  end
end
