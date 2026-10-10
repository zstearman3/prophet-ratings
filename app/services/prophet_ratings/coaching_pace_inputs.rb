# frozen_string_literal: true

module ProphetRatings
  # Fresh capture boundary. Year locks serialize capture against manual review edits.
  class CoachingPaceInputs
    REASONS = %w[eligible no_confirmed_move rejected unsupported_role unconfirmed_full_season
                 unconfirmed_d1 stale_history missing_source_season incomplete_source_season
                 missing_source_team_season invalid_source_pace invalid_source_baseline invalid_signal].freeze

    def initialize(season)
      @season = season
      @changes = []
      @move = @source = nil
    end

    def with_review
      CoachingReview.transaction do
        CoachingReview.with_year_locks([@season.year]) do
          validate_readiness
          yield
        end
      end
    end

    def validate_readiness
      year = @season.year
      return if CoachingReview.find_by(year:)&.ready? && !CoachingChange.exists?(effective_year: year, status: 'pending')

      raise ArgumentError, "Coaching inputs for year=#{year} are not ready; resolve pending candidates and mark CoachingReview ready"
    end

    def capture(team_id, anchor)
      @changes = CoachingChange.where(team_id:, effective_year: @season.year).order(:id).to_a
      @move = @changes.find(&:confirmed?)
      @source = @move&.previous_year ? Season.find_by(year: @move.previous_year) : nil
      captured_operands(anchor)
    end

    def captured_operands(anchor)
      serializer = self.class
      history = @source&.team_seasons&.find_by(team_id: @move&.previous_team_id)
      operands = { target_anchor: serializer.number(anchor), source_adjusted_pace: serializer.number(history&.adj_pace),
                   source_baseline: serializer.number(@source&.average_pace) }
      operands.merge(reason: exclusion(operands.merge(source_team_season_id: history&.id)),
                     moves: @changes.map { |change| serializer.facts(change) },
                     source_season_id: @source&.id, source_team_season_id: history&.id,
                     source_team_id: @move&.previous_team_id)
    end

    def self.facts(change)
      change.attributes.slice('id', *CoachingChange::REVIEW_FIELDS)
    end

    def self.number(value)
      return value unless value.is_a?(Numeric)

      value.finite? ? value.to_f : value.to_s
    end

    def self.usable?(value)
      value.is_a?(Numeric) && value.finite? && value.positive?
    end

    private

    def exclusion(operands)
      return @changes.any? { |change| change.status == 'rejected' } ? 'rejected' : 'no_confirmed_move' unless @move

      move_exclusion || history_exclusion || ('missing_source_team_season' unless operands[:source_team_season_id]) ||
        self.class.numeric_exclusion(operands) || 'eligible'
    end

    def move_exclusion
      return 'unsupported_role' unless @move.previous_role == 'head_coach'
      return 'unconfirmed_full_season' unless @move.full_season_head_coach?
      return 'unconfirmed_d1' unless @move.previous_season_d1?
      return 'stale_history' unless @move.previous_year == @season.year - 1

      nil
    end

    def history_exclusion
      return 'missing_source_season' unless @source
      return 'incomplete_source_season' unless completed_source?

      nil
    end

    def completed_source?
      date = @source.end_date
      date < @season.start_date && date < Game.current_schedule_date
    end

    public_class_method def self.numeric_exclusion(operands)
      pace, baseline, anchor = operands.values_at(:source_adjusted_pace, :source_baseline, :target_anchor)
      return 'invalid_source_pace' unless usable?(pace)
      return 'invalid_source_baseline' unless usable?(baseline)
      return 'invalid_signal' unless usable?(anchor + (pace - baseline))

      nil
    end
  end
end
