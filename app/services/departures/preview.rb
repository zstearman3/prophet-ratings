# frozen_string_literal: true

module Departures
  # Read-only coverage report over a reproducible dataset and a separate reviewed revision.
  class Preview
    def initialize(dataset:, review: {}, identity: TeamIdentity.new)
      @dataset = dataset
      @review = review
      @identity = identity
      Contract.years!(dataset)
      validate_dataset
    end

    def call
      validate_review
      rows = reviewed_rows
      self.class.validate_player_stints(rows)
      report(rows).merge('teams' => team_reports(rows))
    end

    def self.globally_unknown?(row)
      status = row.fetch('status')
      Contract::RESOLVED.exclude?(status) && (status != 'unknown_production' || row.fetch('candidate_team_ids', []).size != 1)
    end

    def self.validate_player_stints(rows)
      stints = rows.flat_map { |row| row.fetch('stints') }
      keys = stints.map { |stint| [stint.fetch('source_id'), stint.fetch('player_source_url')] }
      Contract.unique!(keys, 'school player identities')
    end

    private

    attr_reader :dataset, :review, :identity

    def validate_dataset
      Contract.check!(dataset.fetch('schema') == Contract::VERSION, 'Invalid dataset contract')
      Contract.check!(dataset.fetch('dataset_revision') == Contract.hash(dataset.except('dataset_revision')), 'Invalid dataset hash')
    end

    def reviewed_rows
      decisions = review.fetch('decisions', []).index_by { |entry| entry.fetch('selection_key') }
      dataset.fetch('selections').map do |selection|
        ReviewedSelection.new(selection:, decision: decisions[selection.fetch('selection_key')], dataset:, identity:).call
      end
    end

    def report(rows)
      { 'dataset_revision' => dataset.fetch('dataset_revision'), 'reviewed_revision' => review.present? ? Contract.hash(review) : nil,
        'draft_complete' => draft_complete?, 'coverage_complete' => coverage_complete?(rows),
        'expected_selections' => dataset.fetch('expected_picks').size,
        'accounted_selections' => rows.size, 'status_counts' => rows.group_by { |row| row.fetch('status') }.transform_values(&:size),
        'failures' => dataset.fetch('failures'), 'selections' => rows }
    end

    def coverage_complete?(rows)
      draft_complete? && rows.all? { |row| Contract::RESOLVED.include?(row.fetch('status')) }
    end

    def team_reports(rows)
      complete = draft_complete? && rows.none? { |row| self.class.globally_unknown?(row) }
      identity.ids.map { |team_id| TeamCoverage.new(team_id:, rows:, complete:).call }
    end

    def validate_review
      return if review.empty?

      Contract.check!(review.fetch('dataset_revision') == dataset.fetch('dataset_revision'), 'Review references another dataset')
      validate_approval
      validate_decisions
    end

    def validate_decisions
      keys = review.fetch('decisions').pluck('selection_key')
      Contract.unique!(keys, 'review decisions')
      Contract.check!((keys - dataset.fetch('selections').pluck('selection_key')).empty?,
                      'Review includes undrafted or wrong-year selections')
    end

    def validate_approval
      %w[reviewed_by reviewed_at revision_id].each { |key| Contract.text!(review.fetch(key), key) }
      Time.iso8601(review.fetch('reviewed_at'))
      Contract.check!(review.fetch('decision') == 'approved', 'Require explicit file review approval')
    end

    def draft_complete?
      picks = dataset.fetch('selections').pluck('overall_pick')
      expected = dataset.fetch('expected_picks')
      Contract.check!((picks - expected).empty?, 'Unexpected selections conflict with expected picks')
      picks.sort == expected.sort && dataset.fetch('failures').empty?
    end
  end
end
