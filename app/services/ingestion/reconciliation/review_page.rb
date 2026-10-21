# frozen_string_literal: true

module Ingestion
  module Reconciliation
    # Bounded presentation of an immutable comparison, independent of mutable local rows.
    class ReviewPage
      PAGE_SIZE = 50

      def initialize(report, filters)
        @filters = filters
        @data = page_data
        @source = source_rows(report)
        @matched = @source.select { |row| matches?(row) }
      end

      def entity
        @data.fetch(:entity)
      end

      def page
        @data.fetch(:page)
      end

      def total
        @source.size
      end

      def matched
        @matched.size
      end

      def rows
        @matched.slice((page - 1) * PAGE_SIZE, PAGE_SIZE) || []
      end

      def pages
        [(matched.to_f / PAGE_SIZE).ceil, 1].max
      end

      def self.row_status(row)
        row.fetch('status', row['category'])
      end

      def self.value_matches?(value, query)
        items = value.is_a?(Hash) ? value.values : value
        return items.any? { |item| value_matches?(item, query) } if items.is_a?(Array)

        items.to_s.downcase.include?(query)
      end

      private

      def source_rows(report)
        return [] unless report

        entity == 'shadow' ? report.fetch('shadow').fetch('mismatches') : report.fetch("#{entity}s")
      end

      def page_data
        { entity: @filters['entity'].presence_in(%w[game shadow]) || 'team', page: [@filters['page'].to_i, 1].max }
      end

      def matches?(row)
        matcher = self.class
        status = @filters['status']
        query = @filters['q'].to_s.downcase
        (status.blank? || status == matcher.row_status(row)) && (query.empty? || matcher.value_matches?(row, query))
      end
    end
  end
end
