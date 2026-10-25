# frozen_string_literal: true

module Departures
  # Canonical ordered JSON without assembling the annual production array in Ruby.
  class DatasetStream
    KINDS = %w[selections production failures production_warnings].freeze

    def initialize(record)
      @record = record
    end

    def digest
      output = Digest::SHA256.new
      write(output)
      output.hexdigest
    end

    def write(output)
      output << '{'
      keys = (@record.header.keys + kinds).sort
      keys.each_with_index { |key, index| write_entry(output, key, index) }
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

    def kinds
      header = @record.header
      header['schema'] == CbbdDataset::VERSION && CbbdDataset.reported_totals?(header) ? KINDS : KINDS.first(3)
    end

    def write_entry(output, key, index)
      output << ',' unless index.zero?
      output << JSON.generate(key) << ':'
      if kinds.include?(key)
        write_rows(output, key)
      else
        output << JSON.generate(@record.header.fetch(key), sort_keys: true)
      end
    end

    def write_rows(output, kind)
      output << '['
      rows = @record.rows.where(kind:).order(:ordinal)
      rows.find_each(batch_size: JsonRows::BATCH_SIZE).with_index { |row, index| self.class.write_row(output, row, index) }
      output << ']'
    end

    public_class_method def self.write_row(output, row, index)
      output << ',' unless index.zero?
      output << JSON.generate(row.fact, sort_keys: true)
    end
  end
end
