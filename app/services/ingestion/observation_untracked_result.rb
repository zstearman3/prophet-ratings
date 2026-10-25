# frozen_string_literal: true

module Ingestion
  # Untracked opponents contribute visible results, never inferred statistics or rating inputs.
  class ObservationUntrackedResult
    def initialize(observation, game, scoring_review: nil)
      @data = observation.data
      @game = game
      @scoring_review = scoring_review
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
        ObservationUntrackedBox.new(@data, label, scoring_review: @scoring_review).validate
        if GameObservation.complete_side?(@data[label])
          ProphetRatings::GameBoxScoreValidator.new(transient, label,
                                                    scoring_review: @scoring_review).call
        end
      end
    end

    def validation_context
      Game.new(ObservationWriter.side_attributes(@data).merge(season: Season.find_by(year: @data[:season_year]),
                                                              start_time: @data[:start_time] ||
                                                              Game.schedule_time_for(Date.iso8601(@data[:schedule_date]))))
    end

    def validation_game
      transient = validation_context
      GameObservation::SIDES.each do |label|
        side = @data[label]
        transient.public_send("#{label}_team_game=", TeamGame.new(side[:stats])) if GameObservation.complete_side?(side)
      end
      transient
    end
  end
end
