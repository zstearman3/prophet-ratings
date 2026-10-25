# frozen_string_literal: true

module OffseasonPerformance
  # Installs only the synthetic transport; ordinary application boots never prepend it.
  module Offline
    def self.call(uri, key)
      OfflineResponse.new(uri, key).call
    end
  end

  # Validates the exact provider request before returning consistently remapped fixture rows.
  class OfflineResponse
    def initialize(uri, key)
      @uri = uri
      @key = key
      @path = uri.path
    end

    def call
      validate_request
      { status: 200, body: JSON.generate(rows.map { |row| remap(row) }), headers: {} }
    end

    def validate_request
      query = URI.decode_www_form(@uri.query.to_s).to_h
      expected = { 'season' => '2025', 'startDateRange' => '2024-11-01T04:00:00.000Z',
                   'endDateRange' => '2024-11-02T03:59:59.999Z' }
      return if @key == 'synthetic-offline-only' && @uri.scheme == 'https' && @uri.host == 'api.collegebasketballdata.com' &&
                %w[/games /games/teams].include?(@path) && query == expected

      raise ArgumentError, "Unexpected offline request: #{@path} #{query.inspect}"
    end

    def rows
      fixture = JSON.parse(File.read(File.join(__dir__, '../../spec/fixtures/ingestion/cbbd/final.json')))
      fixture.fetch(@path == '/games' ? 'games' : 'boxes')
    end

    def remap(row)
      klass = self.class
      attributes = @path == '/games' ? klass.game_attributes : klass.box_attributes(row)
      row.merge('season' => 2025, 'startDate' => '2024-11-01T23:00:00Z').merge(attributes)
    end

    def self.game_attributes
      { 'id' => 900_001, 'homeTeamId' => 210, 'awayTeamId' => 220,
        'homeTeam' => 'Synthetic University 021', 'awayTeam' => 'Synthetic University 022' }
    end

    def self.box_attributes(row)
      team, opponent = row.values_at('teamId', 'opponentId').map { |number| number == 10 ? 210 : 220 }
      { 'gameId' => 900_001, 'teamId' => team, 'opponentId' => opponent }
    end
  end
end
