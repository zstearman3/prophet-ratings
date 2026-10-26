# frozen_string_literal: true

module Departures
  # An interrupted transaction never marks a partial source complete; explicit retry replaces incomplete rows only.
  class SourceRowWriter
    ROUTING_KEYS = { 'cbbd_player' => %w[teamId athleteId].freeze, 'cbbd_team' => %w[teamId].freeze }.freeze

    def initialize(record, source)
      @record = record
      @source = source
      @ordinal = 0
    end

    def call
      record.with_lock(requires_new: true) { write { yield self } }
    rescue ArgumentError, KeyError, ActiveRecord::StatementInvalid => error
      record.reload.update!(status: 'failed', failure: error.message)
    end

    def append(batch)
      entries = batch.map { |fact| attributes(fact) }
      validate_keys(entries)
      EvidenceRows.source(entries)
    end

    private

    attr_reader :record, :source

    def write
      return if record.status == 'completed'

      reset
      yield
      complete
    end

    def reset
      record.rows.delete_all(:delete_all)
      record.update!(status: 'running', failure: nil)
    end

    def complete
      digest = DatasetStream.rows_digest(record.rows.order(:ordinal))
      record.update!(status: 'completed', row_count: @ordinal, rows_digest: digest)
    end

    def attributes(fact)
      validate_routing(fact)
      @ordinal += 1
      { departure_source_normalization_id: record.id, ordinal: @ordinal, row_key: row_key(fact),
        provider_team_id: fact['teamId'], provider_player_id: fact['athleteId'], fact: }
    end

    def validate_routing(fact)
      fields = ROUTING_KEYS[source.fetch('type')]
      fields&.each { |field| CbbdValues.id(fact.fetch(field)) }
    end

    def row_key(fact)
      case source.fetch('type')
      when 'cbbd_player' then fact.values_at('athleteId', 'teamId').join('/')
      when 'cbbd_team' then fact.fetch('teamId').to_s
      else @ordinal.to_s
      end
    end

    def validate_keys(entries)
      keys = entries.pluck(:row_key)
      label = "#{source.dig('request', 'seasonType')} #{source['type'] == 'cbbd_player' ? 'athlete/team rows' : 'teams'}"
      Contract.unique!(keys, label)
      Contract.check!(!record.rows.exists?(row_key: keys), "Duplicate #{label}")
    end
  end
end
