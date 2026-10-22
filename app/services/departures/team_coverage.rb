# frozen_string_literal: true

module Departures
  # Validates one team's common denominator and keeps partial loss explicitly null.
  class TeamCoverage
    def initialize(team_id:, rows:, complete:)
      @team_id = team_id
      @rows = rows
      @complete = complete
    end

    def call
      validate_totals
      { 'team_id' => team_id, 'known_points_subtotal' => points, 'team_points' => denominator,
        'loss_share' => if known?
                          denominator ? points.fdiv(denominator) : 0.0
                        end,
        'reason' => reason }
    end

    private

    attr_reader :team_id, :rows, :complete

    def stints
      rows.flat_map { |row| row.fetch('stints') }.select { |stint| stint.fetch('team_id') == team_id }
    end

    def points
      stints.pluck('player_points').sum
    end

    def denominator
      stints.first&.fetch('team_points')
    end

    def known?
      complete && rows.none? do |row|
        Contract::RESOLVED.exclude?(row.fetch('status')) && row.fetch('candidate_team_ids', []).include?(team_id)
      end
    end

    def reason
      return 'unknown_partial_coverage' unless known?

      points.zero? ? 'verified_zero' : 'verified_production'
    end

    def validate_totals
      return if stints.empty?

      denominators = stints.map { |stint| stint.slice('source_id', 'production_key', 'team_points', 'team_minutes') }.uniq
      Contract.check!(denominators.one?, 'Conflicting team denominators')
      Contract.check!(points <= denominator, 'Drafted points exceed team points')
    end
  end
end
