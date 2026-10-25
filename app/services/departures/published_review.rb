# frozen_string_literal: true

module Departures
  # Projects stored display facts in PostgreSQL so the page never loads retained response bodies.
  class PublishedReview
    DATASET_SQL = <<~SQL.squish.freeze
      jsonb_build_object(
        'team_matches', payload #> '{dataset,team_matches}',
        'production_warnings', payload #> '{dataset,production_warnings}',
        'production', (
          SELECT COALESCE(jsonb_agg(
            (production - 'scope_rows' - 'players') || jsonb_build_object('players', (
              SELECT COALESCE(jsonb_agg(player - 'scope_rows' ORDER BY player_position), '[]'::jsonb)
              FROM jsonb_array_elements(production->'players') WITH ORDINALITY AS players(player, player_position)
            )) ORDER BY team_position
          ), '[]'::jsonb)
          FROM jsonb_array_elements(payload #> '{dataset,production}') WITH ORDINALITY AS teams(production, team_position)
        )
      )
    SQL
    REPORT_SQL = <<~SQL.squish.freeze
      jsonb_build_object(
        'teams', payload #> '{report,teams}',
        'selections', (
          SELECT COALESCE(jsonb_agg(selection - 'stints' ORDER BY position), '[]'::jsonb)
          FROM jsonb_array_elements(payload #> '{report,selections}') WITH ORDINALITY AS selections(selection, position)
        )
      )
    SQL

    def initialize(batch)
      @batch = batch
    end

    def call
      facts, report = OffseasonInputRevision.where(id: @batch.revision_id).pick(Arel.sql(DATASET_SQL), Arel.sql(REPORT_SQL))
      DraftTeamReview.present(facts, report, []).merge('review_key' => nil, 'errors' => [])
    end
  end
end
