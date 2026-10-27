# frozen_string_literal: true

module Departures
  # Independently hashes decoded JSONB from storage, preserving integer/float distinctions.
  class PersistedPayload
    def initialize(revision_id)
      @scope = OffseasonInputRevision.where(id: Integer(revision_id))
      @output = nil
    end

    def digest
      @output = Digest::SHA256.new
      write_root
      @output.hexdigest
    end

    def matches?(payload)
      payload.matches_revision?(@scope.pick(:id))
    end

    private

    def write_root
      @output << '{'
      keys.each_with_index { |key, index| write_root_entry(key, index) }
      @output << '}'
    end

    def write_root_entry(key, index)
      self.class.write_key(@output, key, index)
      case key
      when 'dataset' then RevisionDatasetStream.new(@scope, @output).write
      when 'evidence' then write_evidence
      else write_value(@scope.pick(Arel.sql('payload->?', key)))
      end
    end

    def keys
      source = Arel.sql('offseason_input_revisions, LATERAL jsonb_object_keys(payload) AS entries(key)')
      @scope.from(source).order(Arel.sql('key COLLATE "C"')).pluck(Arel.sql('key'))
    end

    public_class_method def self.write_key(output, key, index)
      output << ',' unless index.zero?
      output << JSON.generate(key) << ':'
    end

    def write_value(entry)
      JSON::State.new(sort_keys: true).generate(entry, DatasetStream::JsonOutput.new(@output))
    end

    def write_evidence
      @output << '{'
      SqlCursor.new(evidence_relation, fetch_size: 1).each.with_index { |row, index| write_evidence_entry(row, index) }
      @output << '}'
    end

    def evidence_relation
      source = Arel.sql("offseason_input_revisions, LATERAL jsonb_each(payload->'evidence') AS entries(key, value)")
      @scope.from(source).select(Arel.sql('key, value')).order(Arel.sql('key COLLATE "C"'))
    end

    def write_evidence_entry(row, index)
      self.class.write_key(@output, row.fetch('key'), index)
      write_value(JSON.parse(row.fetch('value')))
    end
  end
end
