# frozen_string_literal: true

module ProphetRatings
  # Recomputes coverage from captured all-selection accounting, never a supplied loss share.
  class DepartureContributionEvidence
    def initialize(evidence, team_id, target_year)
      @evidence = evidence
      @team_id = Departures::Contract.integer!(team_id, 'team_id', minimum: 1)
      @target_year = Departures::Contract.integer!(target_year, 'target_year', minimum: 3)
    end

    def call
      return { 'loss_share' => nil, 'reason' => 'missing_departure_evidence' } unless @evidence

      rows = validated_rows
      complete = self.class.draft_complete?(@evidence, rows) && rows.none? { |row| Departures::Preview.globally_unknown?(row) }
      Departures::TeamCoverage.new(team_id: @team_id, rows:, complete:).call
    end

    def self.capture(revision)
      return unless revision
      raise ArgumentError, 'Require a departure revision' unless revision.kind == 'departures'

      payload = revision.payload
      provenance = revision.attributes.slice('id', 'version', 'input_hash', 'dataset_hash', 'review_hash', 'season_id')
      payload.fetch('dataset').slice('draft_year', 'prior_season_year', 'target_year', 'expected_picks', 'failures', 'sources').merge(
        payload.fetch('report').slice('selections'), 'review' => payload.fetch('review'),
                                                     'revision' => provenance
      )
    end

    def validate_review
      return if OffseasonInputRevision.departures_approved?(@evidence.fetch('review'))

      raise ArgumentError, 'Require approved departure evidence'
    end

    def validated_rows
      Departures::Contract.years!(@evidence)
      Departures::Contract.check!(@evidence.fetch('target_year') == @target_year, 'Departure target year mismatch')
      validate_review
      @evidence.fetch('selections').tap { |rows| self.class.validate_rows(rows, @evidence.fetch('draft_year')) }
    end

    def self.validate_duplicates(rows)
      Departures::Contract.unique!(rows.pluck('selection_key'), 'draft selections')
      Departures::Preview.validate_player_stints(rows)
      Departures::Contract.unique!(rows.flat_map { |row| row.fetch('stints').pluck('player_source_url').uniq }, 'player contributions')
    end

    def self.validate_rows(rows, year)
      validate_duplicates(rows)
      rows.each { |row| validate_selection(row, year) }
      validate_team_ids(rows)
      validate_production(rows)
    end

    def self.validate_team_ids(rows)
      rows.flat_map { |row| selection_team_ids(row) }.each { |id| Departures::Contract.integer!(id, 'team_id', minimum: 1) }
    end

    def self.selection_team_ids(row)
      row.fetch('candidate_team_ids', []) + row.fetch('stints').pluck('team_id')
    end

    def self.validate_production(rows)
      rows.flat_map { |row| row.fetch('stints') }.each { |stint| validate_stint(stint) }
    end

    def self.validate_selection(row, year)
      pick = Departures::Contract.integer!(row.fetch('overall_pick'), 'overall_pick', minimum: 1)
      Departures::Contract.check!(row.fetch('selection_key') == "#{year}/#{pick}", 'Wrong selection year/key')
      Departures::Contract.check!(Departures::Contract::STATUSES.include?(row.fetch('status')), 'Invalid accounting status')
      Departures::ReviewedSelection.validate_stints(row.fetch('stints'), row)
    end

    def self.validate_numbers(stint)
      %w[player_points team_points games].each do |key|
        Departures::Contract.integer!(stint.fetch(key), key, minimum: key == 'player_points' ? 0 : 1)
      end
    end

    def self.validate_stint(stint)
      validate_numbers(stint)
      Departures::Contract.check!(stint.fetch('player_points') <= stint.fetch('team_points'), 'Invalid player/team totals')
      return if stint.fetch('scope') == Departures::Contract::SCOPE && stint.fetch('units') == Departures::ProductionStint::UNITS

      raise ArgumentError, 'Require full-season same-scope production units'
    end

    def self.expected_picks(evidence)
      expected = evidence.fetch('expected_picks')
      Departures::Contract.unique!(expected, 'expected picks')
      expected.each { |pick| Departures::Contract.integer!(pick, 'expected pick', minimum: 1) }
      expected
    end

    def self.draft_complete?(evidence, rows)
      expected = expected_picks(evidence)
      picks = rows.pluck('overall_pick')
      Departures::Contract.check!((picks - expected).empty?, 'Unexpected draft selections')
      expected.present? && picks.sort == expected.sort && evidence.fetch('failures').empty?
    end

    private :validate_review, :validated_rows
  end
end
