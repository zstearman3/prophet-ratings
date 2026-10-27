# frozen_string_literal: true

module Departures
  # The validation snapshot owns rollback. A nested savepoint would retain every source model until commit.
  class FreshSourceRowWriter < SourceRowWriter
    def call
      record.with_lock { write { yield self } }
    end
  end
end
