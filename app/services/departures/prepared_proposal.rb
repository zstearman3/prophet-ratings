# frozen_string_literal: true

module Departures
  # The source-derived dataset is authenticated; this bounded projection preserves all matching rules.
  class PreparedProposal
    # Only the independent full-dataset hash replay is replaced by the worker's prior complete proof.
    class Preview < Departures::Preview
      private

      def validate_dataset
        PlayerIdentity.validate_contract(dataset)
      end
    end

    # The bounded matching inputs travel together through report and presentation calculation.
    Context = Data.define(:data, :document)

    def initialize(operation, record)
      @operation = operation
      @record = record
      @batch = DepartureBatch.select(DepartureBatch.column_names - ['plan']).find(operation.departure_batch_id)
      @season = @batch.season
    end

    def call
      Contract.check!(@record.header.fetch('target_year') == @season.year, 'Departure target season mismatch')
      data = PreparedDataset.new(@record).projection(@batch.decisions)
      context = Context.new(data:, document: document(data))
      projection(context, report(context))
    end

    private

    def projection(context, report)
      persist_inputs(report)
      { report:, choices: choices(context, report) }
    end

    def choices(context, report)
      data, document = context.to_h.values_at(:data, :document)
      { 'review' => document, 'automatic' => CbbdDataset.automatic?(data) }
        .merge(coverage_choices(data)).merge(self.class.player_choices(data, report))
    end

    def coverage_choices(data)
      data['provider'] == 'cbbd' ? { 'coverage' => PreparedCoverage.new(@record).call } : {}
    end

    public_class_method def self.player_choices(data, report)
      CbbdDataset.automatic?(data) ? { 'players' => DraftTeamMatches.present(report.fetch('selections'), data) } : {}
    end

    def document(data)
      { 'dataset_revision' => @record.dataset_revision,
        'decisions' => CbbdDataset.automatic?(data) ? DraftTeamMatches.new(data).call : @batch.decisions,
        'revision_id' => "departure-batch-#{@batch.id}", 'decision' => 'approved',
        'reviewed_by' => 'Draft calculation only; not approved', 'reviewed_at' => @batch.created_at.iso8601(6),
        'partial_acknowledgement' => @batch.acknowledgement }
    end

    def report(context)
      data, document = context.to_h.values_at(:data, :document)
      report = Preview.new(dataset: data, review: document).call
      OffseasonInputs::DepartureBundle.validate_conflicts(data, report)
      report.merge('gaps' => CoverageGaps.new(data, report, @season.team_seasons.pluck(:team_id)).call)
    end

    def persist_inputs(report)
      inputs = report.fetch('teams').index_by { |team| team.fetch('team_id') }
      @season.team_seasons.order(:team_id).pluck(:team_id).each do |team_id|
        input = inputs.fetch(team_id).merge('units' => ProductionStint::UNITS, 'loss_share_unit' => 'fraction_of_team_points')
        @operation.proposals.create!(team_id:, input:)
      end
    end
  end
end
