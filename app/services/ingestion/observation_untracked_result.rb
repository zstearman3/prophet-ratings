# frozen_string_literal: true

module Ingestion
  # Untracked opponents contribute visible results, never inferred statistics or rating inputs.
  class ObservationUntrackedResult
    def initialize(observation, game)
      @data = observation.data
      @game = game
    end

    def call
      validate
      @game.update!(status: :final_unmatched, possessions: nil, minutes: nil, in_conference: false)
    end

    def validate
      validate_scores
      validate_boxes
    end

    private

    def validate_scores
      scores = GameObservation::SIDES.map { |label| @data[label][:score] }
      return unless scores.any?(&:nil?) || scores.uniq.size != 2

      raise GameObservation::Invalid, 'final scores must be present and differ'
    end

    def validate_boxes
      transient = validation_game
      GameObservation::SIDES.each do |label|
        ObservationUntrackedBox.new(@data, label).validate
        ProphetRatings::GameBoxScoreValidator.new(transient, label).call if GameObservation.complete_side?(@data[label])
      end
    end

    def validation_game
      transient = Game.new(ObservationWriter.side_attributes(@data))
      GameObservation::SIDES.each do |label|
        side = @data[label]
        transient.public_send("#{label}_team_game=", TeamGame.new(side[:stats])) if GameObservation.complete_side?(side)
      end
      transient
    end
  end
end
