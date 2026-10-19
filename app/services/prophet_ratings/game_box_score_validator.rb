# frozen_string_literal: true

module ProphetRatings
  # Validates one stored side before any finalized statistics are written.
  class GameBoxScoreValidator
    REQUIRED_COUNTS = %i[field_goals_made field_goals_attempted two_pt_made two_pt_attempted three_pt_made
                         three_pt_attempted free_throws_made free_throws_attempted offensive_rebounds
                         defensive_rebounds rebounds assists steals blocks turnovers fouls points].freeze
    COMPONENTS = {
      points: { two_pt_made: 2, three_pt_made: 3, free_throws_made: 1 },
      field_goals_made: { two_pt_made: 1, three_pt_made: 1 },
      field_goals_attempted: { two_pt_attempted: 1, three_pt_attempted: 1 },
      rebounds: { offensive_rebounds: 1, defensive_rebounds: 1 }
    }.freeze

    def initialize(game, label)
      @game = game
      @label = label
      @side = game.public_send("#{label}_team_game")
    end

    def call
      reject('missing side') unless @side
      validate_inputs
      validate_relationships
      reject('possessions must be finite and positive') unless self.class.positive?(@side.calculated_possessions)
    end

    def self.nonnegative?(value)
      BasketballCalculations::StatFormulae.finite?(value) && value >= 0
    end

    def self.positive?(value)
      BasketballCalculations::StatFormulae.finite?(value) && value.positive?
    end

    private

    def validate_inputs
      REQUIRED_COUNTS.each do |field|
        reject("#{field} must be finite and nonnegative") unless self.class.nonnegative?(@side.public_send(field))
      end
      validate_minutes
      validate_score
    end

    def validate_minutes
      minutes = @side.minutes
      reject('minutes must be finite and positive') unless self.class.positive?(minutes)
      opponent = @game.public_send(@label == :home ? :away_team_game : :home_team_game)
      reject('minutes must equal opponent minutes') if opponent && minutes != opponent.minutes
    end

    def validate_relationships
      %i[two_pt three_pt free_throws field_goals].each do |category|
        made = @side.public_send("#{category}_made")
        attempted = @side.public_send("#{category}_attempted")
        reject("#{category}_made exceeds attempts") if made > attempted
      end
      validate_components
    end

    def validate_components
      COMPONENTS.each do |field, components|
        total = component_total(components)
        reject("#{field} does not equal component total") unless @side.public_send(field) == total
      end
    end

    def component_total(components)
      components.sum { |component, multiplier| @side.public_send(component) * multiplier }
    end

    def validate_score
      score = @game.public_send("#{@label}_team_score")
      reject('score must be finite and nonnegative') unless self.class.nonnegative?(score)
      reject('score does not equal points') unless score == @side.points
    end

    def reject(reason)
      raise GameFinalizer::MissingDerivedStatsError, "Cannot finalize game #{@game.id}: #{@label} #{reason}"
    end
  end
end
