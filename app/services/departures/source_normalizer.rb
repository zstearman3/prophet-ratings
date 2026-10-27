# frozen_string_literal: true

module Departures
  # Parsing is independent of annual reconciliation/extraction policy.
  class SourceNormalizer
    PARSER = 'departure-source-rows-v1'
    # Fresh and cached parsing share extraction while choosing their persistence contracts once.
    Storage = Data.define(:identity, :capture, :writer)

    def initialize(source, bytes, settings, identity: nil)
      @source = source
      @bytes = bytes
      @settings = settings
      @storage = self.class.storage(identity)
    end

    def self.storage(identity)
      return Storage.new(identity:, capture: CaptureStore.method(:capture_reference), writer: FreshSourceRowWriter) if identity

      Storage.new(identity: nil, capture: CaptureStore.method(:capture), writer: SourceRowWriter)
    end

    def call
      validate_metadata
      record = normalization
      write_rows(record) unless record.status == 'completed'
      self.class.projection(record.id)
    end

    def self.projection(id)
      values = DepartureSourceNormalization.where(id:).pick(:id, :status, :rows_digest, :row_count, :failure)
      Contract.check!(values.present?, 'Missing departure source normalization')
      DepartureSourceNormalization::Reference.new(*values)
    end

    private

    attr_reader :source, :settings

    def write_rows(record)
      row_writer(record).call { |writer| write_batches(writer) }
    end

    def row_writer(record)
      @storage.writer.new(record, source)
    end

    def write_batches(writer)
      batches { |batch| writer.append(batch) }
    end

    def validate_metadata
      CbbdSnapshot.new(source:, directory: nil, settings:).validate_metadata if source['snapshot_kind'] == 'raw_json'
    end

    def normalization
      identity = @storage.identity
      capture = @storage.capture.call(@bytes)
      attributes = { departure_source_capture_id: capture.id, contract: source_contract }
      return DepartureSourceNormalization.create!(identity:, **attributes) if identity

      self.class.cached_normalization(capture.sha256, attributes)
    end

    public_class_method def self.cached_normalization(digest, attributes)
      DepartureSourceNormalization.create_or_find_by!(identity: Contract.digest([digest, attributes.fetch(:contract)])) do |row|
        row.assign_attributes(attributes)
      end
    end

    def source_contract
      source.slice('id', 'type', 'request', 'team_name_source', 'scope', 'scope_evidence', 'url')
            .merge('parser' => PARSER, 'year' => settings.fetch('prior_season_year'))
    end

    def batches(&)
      return JsonRows.new(@bytes).each_batch(&) if source.fetch('snapshot_kind') == 'raw_json'

      legacy_rows.each_slice(JsonRows::BATCH_SIZE, &)
    end

    def legacy_rows
      Dir.mktmpdir('departure-source-') do |directory|
        Contract.write_bytes(File.join(directory, source.fetch('snapshot_location')), @bytes)
        parsed = SourceSnapshot.new(source:, directory:, settings:).call
        unpack_legacy(parsed)
      end
    end

    public_class_method def self.validate_legacy(failure)
      Contract.check!(!failure, failure)
    end

    def unpack_legacy(parsed)
      self.class.validate_legacy(parsed['failure'])
      rows = parsed.fetch('rows')
      source['type'] == 'nba_results' ? rows : [rows].compact
    end
  end
end
