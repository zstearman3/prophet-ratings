# frozen_string_literal: true

module Ingestion
  module Cbbd
    # The file adapter's evidence envelope is translated without inventing missing inputs.
    class ImportObservation
      REVISION = "cbbd-import-v1-normalization-#{CanonicalObservation::NORMALIZATION_VERSION}".freeze

      def initialize(row, season)
        @row = row
        @season = season
      end

      def call
        observation = GameObservation.new(payload)
        reasons = ImportValidation.new(row).reasons
        return ObservationAudit.new(observation, nil).retain('invalid', reasons.join('; ')).merge(final_box: 'invalid') if reasons.any?

        report = GameObservationImporter.new(observation:, season: @season).call
        report.merge(final_box: result_coverage(report))
      end

      def payload
        metadata.merge(home: side('home'), away: side('away'), venue:, raw_payload: row,
                       payload_digest: Digest::SHA256.hexdigest(row.to_json), duration_minutes: duration)
      end

      def self.participant(values)
        { name: values['source_name'], external_team_id: values['source_team_id']&.to_s, score: values.dig('score', 'value'),
          stats: GameObservation::STAT_KEYS.index_with { |key| values.dig('stats', key.to_s, 'value') } }
      end

      private

      attr_reader :row

      def metadata
        { contract_version: row['format'], semantic_profile: row['semantic_profile'], provider: row['provider'],
          adapter_revision: REVISION, external_game_id: row['source_game_id']&.to_s, season_year: row['season'],
          schedule_date: row['schedule_date'], start_time: row['start_time'], source_status: row['status'],
          source_completed: row['source_completed'], completion_evidence: row['completion_evidence'],
          captured_at: row.fetch('provenance').first.fetch('captured_at'), source_updated_at: row['source_updated_at'] }
      end

      def side(label)
        self.class.participant(row.fetch(label))
      end

      def duration
        minutes = row.dig('home', 'stats', 'minutes', 'value')
        SportsReferenceObservationAdapter.duration(minutes)
      end

      def venue
        attrs = { venue_name: row.dig('venue', 'name') }
        return attrs unless row.dig('venue', 'certainty') == 'neutral'

        attrs.merge(venue_type: 'neutral', neutral: true, venue_confidence: 'confirmed', venue_source: 'cbbd')
      end

      def complete_boxes?
        %w[home away].all? { |label| GameObservation.complete_side?(side(label)) }
      end

      def result_coverage(report)
        outcome, game_id = report.values_at(:outcome, :game_id)
        return 'not_applicable' if %w[final unchanged].include?(outcome) && Game.final_unmatched.exists?(id: game_id)

        box_coverage
      end

      def box_coverage
        return 'not_final' unless row['status'] == 'final'

        complete_boxes? ? 'complete' : 'missing'
      end
    end
  end
end
