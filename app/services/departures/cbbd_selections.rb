# frozen_string_literal: true

module Departures
  # CBBD athlete IDs are typed identities; nullable IDs never imply nonparticipation.
  class CbbdSelections
    def initialize(rows, settings)
      @rows = rows
      @year = settings.fetch('draft_year')
    end

    def call
      result = @rows.map { |row| selection(row) }
      self.class.validate_result(result)
    end

    def self.validate_result(result)
      Contract.unique!(result.pluck('overall_pick'), 'draft picks')
      Contract.unique!(result.pluck('provider_athlete_id').compact, 'draft athletes')
      validate_round_picks(result)
      result.sort_by { |row| row.fetch('overall_pick') }
    end

    def self.validate_round_picks(result)
      Contract.unique!(result.map { |row| row.values_at('round', 'round_pick') }, 'round picks')
    end

    private

    def selection(row)
      validate_row(row)
      parser = self.class
      parser.provider_identity(row).merge(parser.selection_fields(row, @year))
    end

    def validate_row(row)
      Contract.check!(row.fetch('year') == @year, 'Wrong draft year')
      pick = Contract.integer!(row.fetch('overall'), 'overall pick', minimum: 1)
      round = Contract.integer!(row.fetch('round'), 'round', minimum: 1)
      Contract.check!(pick <= 60 && round <= 2, 'Invalid draft pick/round')
      self.class.validate_name_pick(row)
    end

    public_class_method def self.validate_name_pick(row)
      Contract.integer!(row.fetch('pick'), 'round pick', minimum: 1)
      Contract.text!(row.fetch('name'), 'draft player name')
    end

    public_class_method def self.provider_id(row, key)
      value = row[key]
      Contract.integer!(value, 'CBBD ID', minimum: 1) if value
      value
    end

    public_class_method def self.provider_identity(row)
      { 'provider' => 'cbbd', 'provider_athlete_id' => provider_id(row, 'athleteId'),
        'provider_team_id' => provider_id(row, 'sourceTeamCollegeId') }
    end

    public_class_method def self.selection_fields(row, year)
      pick = row.fetch('overall')
      { 'selection_key' => "#{year}/#{pick}", 'overall_pick' => pick, 'round' => row.fetch('round'), 'round_pick' => row['pick'],
        'player_name_source' => row['name'],
        'affiliation_source' => row.values_at('sourceTeamLocation', 'sourceTeamName').compact.join(' '),
        'source_id' => 'draft', 'source_row' => row }
    end
  end
end
