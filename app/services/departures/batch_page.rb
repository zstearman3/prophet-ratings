# frozen_string_literal: true

module Departures
  # Request-scoped rendering data; mutation services always reload their own current state.
  class BatchPage
    def initialize(batch)
      @batch = batch
      @attempt = batch.attempt
      @teams = Team.includes(:team_aliases).order(:school, :id).to_a
    end

    def call
      review = BatchReview.new(batch)
      { attempt:, history:, report: review.report(attempt:), review_key: review.review_key(attempt:),
        identity: TeamIdentity.new(teams:), teams:, teams_by_id: teams.index_by(&:id),
        row_issues: DecisionForm.new(facts).issues(batch.decisions), production_options: production_options }
    end

    def self.listing(season)
      latest_status = '(SELECT status FROM departure_acquisitions WHERE departure_batch_id = departure_batches.id ORDER BY id DESC LIMIT 1)'
      DepartureBatch.where(season:).select(:id, :status, Arel.sql("#{latest_status} AS acquisition_status")).order(id: :desc)
    end

    private

    attr_reader :batch, :attempt, :teams

    def facts
      attempt&.dataset || {}
    end

    def history
      batch.acquisitions.order(:id).select(:id, :status, :manifest, :started_at, :finished_at, :predecessor_id, :failure,
                                           Arel.sql("dataset->'failures' AS source_failures"))
    end

    def production_options
      facts.fetch('production', []).flat_map { |table| self.class.table_options(table) }
    end

    public_class_method def self.table_options(table)
      denominator = table.fetch('team_points')
      source_id = table.fetch('source_id')
      table.fetch('players').map do |player|
        label = "#{table.fetch('team_name_source')} · #{player['player_name_source']} · " \
                "#{player['player_points']} points / #{denominator} · #{player['player_minutes']} minutes · #{player['games']} games"
        [label, "#{source_id}|#{player.fetch('player_source_url')}"]
      end
    end
  end
end
