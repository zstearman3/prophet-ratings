# frozen_string_literal: true

module Departures
  # Request-scoped rendering data; mutation services always reload their own current state.
  class BatchPage
    def initialize(batch)
      @batch = batch
      @teams = Team.includes(:team_aliases).order(:school, :id).to_a
    end

    def call
      return legacy_review unless DraftTeamReview.applicable?(batch)

      batch.status == 'published' ? published_page : draft_team_page
    end

    def legacy_review
      review = BatchReview.new(batch)
      { attempt:, history:, report: review.report(attempt:), review_key: review.review_key(attempt:),
        dataset: facts, identity: TeamIdentity.new(teams:), teams:, teams_by_id: teams.index_by(&:id),
        row_issues: DecisionForm.new(facts).issues(batch.decisions), production_options: production_options,
        coverage: coverage_report, capture_only: CapturePreparation.capture_only?(batch.plan) }
    end

    def self.listing(season)
      latest_status = '(SELECT status FROM departure_acquisitions WHERE departure_batch_id = departure_batches.id ORDER BY id DESC LIMIT 1)'
      DepartureBatch.where(season:).select(:id, :status, Arel.sql("#{latest_status} AS acquisition_status")).order(id: :desc)
    end

    private

    attr_reader :batch, :teams

    def attempt
      @attempt ||= batch.attempt
    end

    def published_page
      { attempt: nil, history:, draft_team_review: PublishedReview.new(batch).call, teams_by_id: teams.index_by(&:id) }
    end

    def draft_team_page
      report = if attempt&.terminal? && attempt.manifest.present?
                 DraftTeamReview.new(batch, attempt:).report
               else
                 {}
               end
      { attempt:, history:, draft_team_review: report, teams_by_id: teams.index_by(&:id) }
    end

    def coverage_report
      CoverageReview.new(batch).report(attempt:) if batch.plan['provider'] == 'cbbd' && attempt&.terminal?
    end

    def facts
      return {} unless attempt

      saved = attempt.dataset
      return saved unless saved['storage_version'] == StoredDataset::VERSION

      @facts ||= RetainedEvidence.new(attempt).dataset
    end

    def history
      batch.acquisitions.order(:id).select(:id, :status, :manifest, :started_at, :finished_at, :predecessor_id, :failure,
                                           Arel.sql("dataset->'failures' AS source_failures"))
    end

    def production_options
      production_tables.flat_map { |table| self.class.table_options(table) }
    end

    def production_tables
      tables = facts.fetch('production', [])
      return tables unless facts['provider'] == 'cbbd'

      athletes = facts.fetch('selections').pluck('provider_athlete_id').compact
      tables.filter_map { |table| self.class.drafted_players(table, athletes) }
    end

    public_class_method def self.drafted_players(table, athletes)
      players = table.fetch('players').select { |player| athletes.include?(player['provider_athlete_id']) }
      table.merge('players' => players) if players.any?
    end

    public_class_method def self.table_options(table)
      denominator = table.fetch('team_points') || 'Unknown'
      table.fetch('players').map do |player|
        label = "#{table.fetch('team_name_source')} · #{player['player_name_source']} · " \
                "#{player['player_points'] || 'Unknown'} points / #{denominator} · " \
                "#{player['player_minutes']} minutes · #{player['games']} games"
        [label, PlayerIdentity.choice(table, player)]
      end
    end
  end
end
