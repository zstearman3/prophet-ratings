# frozen_string_literal: true

module Ingestion
  module Reconciliation
    # A deterministic offline artifact; no acquisition or canonical writes occur here.
    class Comparison
      VERSION = 1
      READ_MODELS = [Season, Team, TeamAlias, TeamSeason, Game, TeamGame, TeamExternalIdentity, GameExternalIdentity].freeze

      def initialize(season:, replay:)
        @season = season
        @replay = replay.deep_stringify_keys
        @bounds = Cbbd::Bounds.new(**@replay.fetch('bounds').slice('season', 'start_date', 'end_date').symbolize_keys)
        raise ArgumentError, 'Local season does not match replay' unless season.year == @bounds.season
      end

      def call
        teams = TeamCandidates.new(season: @season, observations: observations).call
        local = LocalEvidence.new(season: @season, bounds: @bounds)
        games = GameCandidates.new(season: @season, observations: observations, teams:, local:).call
        mark_out_of_bounds(games)
        { 'version' => VERSION, 'season_id' => @season.id, 'bounds' => @bounds.to_h, 'source' => @replay.except('observations'),
          'teams' => teams, 'games' => games, 'local_duplicates' => local.duplicates,
          'coverage' => coverage(teams, games), 'shadow' => Shadow.new(games:).call, 'fingerprint' => fingerprint(games, local) }
      end

      def fingerprint(games, local)
        ids = (games.flat_map { |row| row['candidate_ids'] } + local.window_games.ids).uniq.sort
        SeasonMembershipProposal.digest([VERSION, @replay, fingerprint_rows(ids)])
      end

      def self.bound_row(row, range)
        return if range.cover?(row.dig('observation', 'schedule_date').to_s)

        row['status'] = 'conflicting'
        row['conflicts'] << 'outside_requested_window'
      end

      private

      def observations
        @replay.fetch('observations')
      end

      def coverage(teams, games)
        source_count = observations.size
        { 'source_observations' => source_count, 'source_game_ids' => games.size, 'source_team_ids' => teams.size,
          'source_team_occurrences' => source_count * 2, 'games_by_status' => games.pluck('status').tally,
          'teams_by_status' => teams.pluck('status').tally, 'acquisition_complete' => @replay['complete'] == true,
          'acquisition_decisions' => @replay.dig('acquisition', 'decisions') || [],
          'orphan_boxes' => @replay.fetch('orphan_boxes', []).size }
      end

      def mark_out_of_bounds(games)
        first, last = @bounds.to_h.values_at('start_date', 'end_date')
        games.each do |row|
          Comparison.bound_row(row, first..last)
        end
      end

      def fingerprint_rows(ids)
        [@season.reload.attributes, Team.order(:id).map(&:attributes), TeamAlias.order(:id).map(&:attributes),
         @season.team_seasons.order(:id).map(&:attributes), Game.where(id: ids).order(:id).map(&:attributes),
         TeamGame.where(game_id: ids).order(:id).map(&:attributes),
         TeamExternalIdentity.where(provider: 'cbbd').order(:id).map(&:attributes),
         GameExternalIdentity.where(provider: 'cbbd').order(:id).map(&:attributes)]
      end
    end
  end
end
