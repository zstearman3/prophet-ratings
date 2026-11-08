# frozen_string_literal: true

module GamesHelper
  def performance_percentage(value)
    value ? number_to_percentage(value * 100, precision: 1) : 'N/A'
  end

  def performance_units(value)
    format('%+.3fu', value)
  end
end
