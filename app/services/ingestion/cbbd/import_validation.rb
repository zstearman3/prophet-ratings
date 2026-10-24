# frozen_string_literal: true

module Ingestion
  module Cbbd
    # Incomplete boxes may be visible for untracked opponents; invalid source evidence is never missingness.
    class ImportValidation
      MISSING_FIELD = /\A[a-z_]+: (?:absent|source_null|blank)\z/

      def initialize(row)
        @row = row
        @minutes = %w[home away].index_with { |label| row.dig(label, 'stats', 'minutes', 'value') }
      end

      def reasons
        conflicts = @row['conflicts'].to_a
        return conflicts unless @row['status'] == 'final'

        (conflicts + @row['reasons'].to_a.reject { |reason| missing_only?(reason) }).uniq
      end

      private

      def missing_only?(reason)
        return true if MISSING_FIELD.match?(reason)
        return @minutes.values.any?(NilClass) if reason == 'side minutes disagree'

        label = reason[/\A(home|away) period duration disagreement\z/, 1]
        label && @minutes[label].is_a?(NilClass)
      end
    end
  end
end
