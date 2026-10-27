# frozen_string_literal: true

module Departures
  # Canonical ordered JSON without assembling the annual production array in Ruby.
  class DatasetStream
    # JSON's streaming API writes bounded buffers; callers use the append interface.
    JsonOutput = Struct.new(:output) do
      def write(bytes)
        output << bytes
        bytes.bytesize
      end

      def flush
        self
      end
    end

    KINDS = %w[selections production failures production_warnings].freeze

    def initialize(record, keys: [])
      @record = record
      @additional_keys = keys
    end

    def digest
      output = Digest::SHA256.new
      write(output)
      output.hexdigest
    end

    def write(output)
      output << '{'
      entries.each_with_index { |key, index| write_entry(output, key, index) }
      output << '}'
    end

    def expand
      kinds.each_with_object(@record.header.dup) do |kind, dataset|
        dataset[kind] = @record.rows.where(kind:).order(:ordinal).pluck(:fact)
      end.merge('dataset_revision' => @record.dataset_revision)
    end

    def self.rows_digest(rows)
      digest = Digest::SHA256.new
      rows.find_each(batch_size: JsonRows::BATCH_SIZE) { |row| digest << JSON.generate(row.fact, sort_keys: true) << "\n" }
      digest.hexdigest
    end

    private

    attr_reader :record

    def kinds
      header = header_metadata
      header['schema'] == CbbdDataset::VERSION && CbbdDataset.reported_totals?(header) ? KINDS : KINDS.first(3)
    end

    def header_metadata
      @record.header
    end

    def entries
      (header_keys + kinds + @additional_keys).sort
    end

    def write_entry(output, key, index)
      output << ',' unless index.zero?
      output << JSON.generate(key) << ':'
      if key == 'dataset_revision'
        output << JSON.generate(@record.dataset_revision)
      elsif kinds.include?(key)
        write_rows(output, key)
      else
        write_header(output, key)
      end
    end

    def header_keys
      @record.header.keys
    end

    def write_header(output, key)
      JSON::State.new(sort_keys: true).generate(@record.header.fetch(key), JsonOutput.new(output))
    end

    def write_rows(output, kind)
      output << '['
      rows = @record.rows.where(kind:).order(:ordinal).skip_query_cache!
      rows.find_each(batch_size: JsonRows::BATCH_SIZE).with_index { |row, index| self.class.write_row(output, row, index) }
      output << ']'
    end

    public_class_method def self.write_row(output, row, index)
      output << ',' unless index.zero?
      output << JSON.generate(row.fact, sort_keys: true)
    end
  end
end
