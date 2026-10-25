# frozen_string_literal: true

module Ingestion
  # Missing counts remain unknown, but every supplied checkable relationship must hold.
  class ObservationUntrackedBox
    def initialize(data, label)
      @data = data
      @label = label
      @side = data.fetch(label)
      @stats = @side.fetch(:stats)
    end

    def validate
      validate_points
      validate_scoring_components
      validate_components
      validate_attempts
      validate_minutes
    end

    def self.component_total(components, stats)
      values = stats.values_at(*components.keys)
      return unless values.all?

      values.zip(components.values).sum { |value, multiplier| value * multiplier }
    end

    private

    def validate_points
      points = @stats[:points]
      reject('score does not equal points') if points && points != @side[:score]
    end

    def validate_scoring_components
      total = self.class.component_total(ProphetRatings::GameBoxScoreValidator::COMPONENTS.fetch(:points), @stats)
      reject('score does not equal scoring component total') if total && total != @side[:score]
    end

    def validate_components
      ProphetRatings::GameBoxScoreValidator::COMPONENTS.each do |field, components|
        value = @stats[field]
        total = self.class.component_total(components, @stats)
        reject("#{field} does not equal component total") if value && total && value != total
      end
    end

    def validate_attempts
      %i[two_pt three_pt free_throws field_goals].each do |category|
        made, attempted = @stats.values_at(:"#{category}_made", :"#{category}_attempted")
        reject("#{category}_made exceeds attempts") if made && attempted && made > attempted
      end
    end

    def validate_minutes
      minutes = @stats[:minutes]
      return unless minutes

      reject('minutes inconsistent with college duration') unless minutes >= 200 && ((minutes - 200) % 25).zero?
      duration = GameObservation.count(@data[:duration_minutes])
      reject('side minutes inconsistent with duration') if duration && minutes != duration * 5
    end

    def reject(reason)
      raise GameObservation::Invalid, "#{@label} #{reason}"
    end
  end
end
