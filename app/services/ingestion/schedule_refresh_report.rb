# frozen_string_literal: true

module Ingestion
  # Deliberately excludes raw payloads, source errors, URLs, paths and credentials.
  class ScheduleRefreshReport
    REASONS = %w[missing_stable_game_identity_projection canonical_values_unchanged unknown_source_freshness
                 unmatched_team ambiguous_team invalid_source_identity possible_reschedule date_rolled_back game_rolled_back
                 multiple_or_cross_season_candidates ambiguous_stored_participant ambiguous_participant unmatched_participant
                 participant_or_orientation_conflict invalid_season_context missing_stable_game_identity missing_team_season
                 unmapped_external_team_identity schedule_projection_requires_pending_game missing_schedule_document_url
                 missing_accepted_provenance provider_or_profile_conflict older_source_revision equal_source_revision_conflict
                 superseded_game_identity missing_required_box_data source_scheduled source_live source_final
                 source_postponed source_cancelled reviewed_source_changed reviewed_game_changed admin_reviewed_scoring].freeze
    NUMBERS = %w[changed_rows ignored_observations imported_rows attempted_rows attempts retries accepted protected rejected unmatched
                 incomplete].freeze
    FLAGS = %w[complete valid_empty rolled_back retrieval_complete acquisition_complete accepted projected scheduled applied].freeze
    IDS = %w[rejection_observation_ids game_id observation_id absent_ids possible_move_ids].freeze
    OUTCOMES = %w[scheduled live final postponed cancelled unknown projected unchanged created updated invalid ambiguous conflict unmatched
                  incomplete stale superseded protected].freeze

    def self.call(report)
      source = report.deep_stringify_keys
      safe = source.each_with_object({}) do |(key, value), result|
        sanitized = sanitize(key, value)
        result[key] = sanitized
      end.compact
      safe.merge(changes(source))
    end

    def self.changes(source)
      games = source['games']
      return {} unless games.is_a?(Array)

      { 'changed_rows' => games.count { |game| game['applied'] && game['outcome'] != 'unchanged' } }
    end

    def self.sanitize(key, value)
      return value if FLAGS.include?(key) && [true, false].include?(value)
      return number(value) if NUMBERS.include?(key)
      return identifier(value) if IDS.include?(key)
      return safe_text(key, value) if %w[date error outcome reason status].include?(key)

      nested(key, value)
    end

    def self.nested(key, value)
      return value.map { |row| call(row) } if %w[days games].include?(key) && value.is_a?(Array)
      return nested_hash(key, value) if value.is_a?(Hash)

      nil
    end

    def self.nested_hash(key, value)
      return scope(value) if key == 'scope'
      return acquisition(value) if key == 'acquisition'
      return counts(value) if %w[counts outcomes final_box_coverage].include?(key)

      nil
    end

    def self.scope(value)
      allowed = { 'provider' => %w[cbbd sports_reference], 'contract_version' => [GameObservation::VERSION],
                  'semantic_profile' => GameObservation::PROFILES,
                  'adapter_revision' => ['sports-reference-bridge-v1', Cbbd::ImportObservation::REVISION] }
      value.select { |key, entry| allowed.fetch(key, []).include?(entry) }
    end

    def self.acquisition(value)
      reasons = value.fetch('failures', []).pluck('reason') & %w[quota request_budget timeout transport authentication
                                                                 authorization malformed saturated_minimum_interval conflicting_duplicate]
      counts(value).merge('failure_reasons' => reasons)
    end

    def self.safe_text(key, value)
      { 'date' => date(value), 'status' => %w[skipped completed failed].include?(value) ? value : nil,
        'error' => value && 'Source acquisition or reconciliation failed; inspect private evidence and identity review.',
        'outcome' => OUTCOMES.include?(value) ? value : nil, 'reason' => reason(value) }[key]
    end

    def self.date(value)
      string = value.to_s
      string if string.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    end

    def self.reason(value)
      known = REASONS & value.to_s.split(/; |: /)
      known.presence&.join('; ') || 'source_evidence_requires_review'
    end

    def self.number(value)
      value if value.is_a?(Integer) && value >= 0
    end

    def self.identifier(value)
      return number(value) unless value.is_a?(Array)

      value.filter_map { |id| number(id) }
    end

    def self.counts(value)
      value.slice(*(NUMBERS + OUTCOMES + %w[complete missing invalid not_final not_applicable unknown])).select do |_key, entry|
        entry.is_a?(Integer) || [true, false].include?(entry)
      end
    end
  end
end
