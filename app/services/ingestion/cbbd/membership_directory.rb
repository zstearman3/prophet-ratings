# frozen_string_literal: true

module Ingestion
  module Cbbd
    # Season-filtered affiliations are evidence, never proof of a complete D1 roster.
    class MembershipDirectory
      def initialize(source_year:, **options)
        @year = SeasonPreparer.parse_year(source_year)
        @options = GameSyncPolicy.new('cbbd', options).options
      end

      def call
        store = CaptureStore.new(@options.fetch(:capture_directory))
        client = Client.new(store:, **@options.except(:capture_directory))
        result = client.request('endpoint' => '/teams/directory', 'season' => @year)
        unless result['outcome'] == 'success'
          raise ArgumentError,
                "CBBD directory acquisition failed: #{result.fetch('outcome')}; prior proposal preserved."
        end

        { 'provider' => 'cbbd', 'source_url' => "https://api.collegebasketballdata.com/teams/directory?season=#{@year}",
          'captured_at' => Time.current.iso8601, 'source_rows' => self.class.normalize(result.fetch('rows'), @year),
          'acquisition' => { 'version' => 1, 'endpoint' => '/teams/directory', 'requested_season' => @year,
                             'captures' => client.captures,
                             'coverage' => 'Unverified complete roster; manual target-year verification required.' } }
      end

      def self.normalize(document, year)
        expected = { 'season' => year }
        raise ArgumentError, 'CBBD directory must echo the requested season exactly.' unless document.slice('season') == expected

        conferences = indexed(document['conferences'], 'conference')
        indexed(document['teams'], 'school').map { |id, source| source_row(id, source, conferences) }
      end

      def self.source_row(id, source, conferences)
        conference_id = stable_id(source['conferenceId'])
        conference = conferences[conference_id]
        raise ArgumentError, "CBBD school #{id}: missing conference metadata; verify coverage manually." unless conference

        { team_external_id: id, team_name: label(source['school']), conference_external_id: conference_id,
          conference_name: label(conference['name']), conference_abbreviation: conference['abbreviation'].to_s }
      end

      def self.indexed(rows, kind)
        unless rows.is_a?(Array) && rows.present? && rows.all?(Hash)
          raise ArgumentError, "CBBD directory has empty or malformed #{kind} coverage; verify source availability."
        end

        rows.each_with_object({}) do |row, result|
          id = validated_id(row, kind)
          raise ArgumentError, "CBBD directory contains duplicate #{kind} ID #{id}." if result.key?(id)

          result[id] = row
        end
      end

      def self.validated_id(row, kind)
        label(row[{ 'conference' => 'name', 'school' => 'school' }.fetch(kind)])
        stable_id(row['id'])
      end

      def self.stable_id(value)
        return value if value.is_a?(String) && value.present? && value == value.strip

        integer = Integer(value, exception: false)
        return integer.to_s if integer&.positive? && integer == value

        raise ArgumentError, 'CBBD directory requires nonblank stable IDs (positive integers or strings).'
      end

      def self.label(value)
        return value if value.is_a?(String) && value.strip.present?

        raise ArgumentError, 'CBBD directory requires school and conference labels; finish metadata manually.'
      end
    end
  end
end
