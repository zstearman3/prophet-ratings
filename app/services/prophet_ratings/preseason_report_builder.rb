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

    # Bind every operand while serializing at most one team's evidence at a time.
    def self.fingerprint(report)
      teams = report.fetch('teams', report[:teams])
      identity = report.except('teams', :teams, 'largest_movers', :largest_movers).as_json
      identity['teams'] = teams.map { |entry| Departures::Contract.digest(entry.as_json) }
      Departures::Contract.digest(identity)
    end

    def self.prior_for_report(row)
      id = row.preseason_prior_id
      return unless id

      PreseasonPrior.select(:id, :outputs, Arel.sql("jsonb_build_object('profile', inputs -> 'profile') AS inputs"))
                    .find_by(id:)
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
