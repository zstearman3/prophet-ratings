# frozen_string_literal: true

module ProphetRatings
  # Capture current approved profile pointers under the caller's season transaction/lock.
  class ReviewedEfficiencyInputs
    def initialize(team_season, revisions: ReviewedInputRevisions.new)
      @team_season = team_season
      @revisions = revisions
      @profile = revisions.bind(team_season.team_offseason_profile)
    end

    def capture(inputs, config)
      @profile&.validate_revision_evidence
      serializer = self.class
      normalized = inputs.merge(previous_values: serializer.numeric_operands(inputs.fetch(:previous_values)),
                                baselines: serializer.numeric_operands(inputs.fetch(:baselines)))
      reviewed = normalized.merge(contract: 'preseason-v3-reviewed-efficiency', team_id: @team_season.team_id,
                                  target_year: @team_season.season.year, reviewed_recruiting: recruiting,
                                  reviewed_departures: departures, baseline_sources: baseline_sources(inputs))
      reviewed.merge(efficiency_adjustment: ReviewedEfficiencyAdjustment.new(reviewed, config).call)
    end

    private

    public_class_method def self.numeric_operands(values)
      values.values.compact.each { |value| PreseasonPriorFormula.finite_efficiency(value) }
      values.transform_values { |value| value&.to_f }
    end

    def recruiting
      revision = @profile&.recruiting_revision
      return unless revision

      serializer = self.class
      @revisions.validate(revision)
      revision.team_input(@team_season.team_id).merge('revision' => serializer.revision_identity(revision),
                                                      'review' => ReviewedInputRevisions.approval(revision.payload.fetch('review')))
    end

    def departures
      revision = @profile&.departure_revision
      return unless revision

      @revisions.validate(revision)
      @revisions.departures(revision)
    end

    public_class_method def self.validate_revision(revision)
      return if revision.valid?

      raise ArgumentError, "Invalid reviewed revision #{revision.id}: #{revision.errors.full_messages.join('; ')}"
    end

    public_class_method def self.revision_identity(revision)
      revision.attributes.except('payload').as_json
    end

    def baseline_sources(inputs)
      source = inputs.fetch(:previous_season)
      attributes = source&.fetch(:attributes) || {}
      serializer = self.class
      { 'adj_offensive_efficiency' => serializer.efficiency_source(attributes, 'adj_offensive_efficiency'),
        'adj_defensive_efficiency' => serializer.efficiency_source(attributes, 'adj_defensive_efficiency'),
        'adj_pace' => attributes['average_pace'] ? 'previous_season.average_pace' : 'configuration.preseason.fallback_pace' }
    end

    public_class_method def self.efficiency_source(attributes, stat)
      return "previous_season.avg_#{stat}" if attributes["avg_#{stat}"]
      return 'previous_season.average_efficiency' if attributes['average_efficiency']

      'configuration.preseason.fallback_efficiency'
    end
  end
end
