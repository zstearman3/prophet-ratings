# frozen_string_literal: true

module Departures
  # Describes the exact partial coverage being acknowledged, independently of hard errors.
  class CoverageGaps
    def initialize(dataset, report, team_ids)
      @dataset = dataset
      @report = report
      @team_ids = team_ids
    end

    def call
      unresolved + missing + failures + unknown_teams
    end

    def self.selection_gap(row)
      status = row.fetch('status')
      "Selection #{row.fetch('selection_key')}: #{status}" unless Contract::RESOLVED.include?(status)
    end

    def self.acknowledgement(gaps, attributes, reviewer)
      return {} if gaps.empty?

      Contract.check!(attributes['acknowledge_gaps'] == '1', 'Acknowledge the displayed partial coverage gaps')
      { 'gaps' => gaps, 'digest' => Contract.digest(gaps), 'reviewed_by' => reviewer, 'reviewed_at' => Time.current.iso8601(6) }
    end

    def self.source_gap(source)
      "Source #{source.fetch('id')}: #{source.fetch('failure')}"
    end

    def self.team_gap(row)
      "Team #{row.fetch('team_id')}: unknown loss" if row['loss_share'].blank?
    end

    private

    attr_reader :dataset, :report, :team_ids

    def unresolved
      report.fetch('selections').filter_map { |row| self.class.selection_gap(row) }
    end

    def missing
      (dataset.fetch('expected_picks') - report.fetch('selections').pluck('overall_pick')).map { |pick| "Missing expected pick #{pick}" }
    end

    def failures
      dataset.fetch('failures').map { |source| self.class.source_gap(source) }
    end

    def unknown_teams
      report.fetch('teams').filter_map do |row|
        self.class.team_gap(row) if team_ids.include?(row['team_id'])
      end
    end
  end
end
