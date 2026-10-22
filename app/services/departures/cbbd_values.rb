# frozen_string_literal: true

module Departures
  # Provider totals retain exact integral points/games and finite audit minutes.
  module CbbdValues
    def self.id(value)
      Contract.integer!(value, 'CBBD ID', minimum: 1)
    end

    def self.whole(value, name)
      valid = value.is_a?(Numeric) && value.finite? && value >= 0
      integer = value.to_i if valid
      Contract.check!(valid && value == integer, "Invalid #{name}")
      integer
    end

    def self.optional_whole(value, name)
      case value
      when NilClass then nil
      else whole(value, name)
      end
    end

    def self.sum_whole(rows, key)
      values = rows.pluck(key)
      values.sum if values.all?(Integer)
    end

    def self.optional_minutes(value)
      case value
      when NilClass then nil
      else minutes(value, 'team game-clock minutes')
      end
    end

    def self.minutes(value, name)
      Contract.check!(value.is_a?(Numeric) && value.finite? && value >= 0, "Invalid #{name}")
      value
    end
  end
end
