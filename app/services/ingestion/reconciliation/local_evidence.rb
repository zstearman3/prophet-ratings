# frozen_string_literal: true

module Ingestion
  module Reconciliation
    # Scopes large local tables to the bounded window and reviewed candidate games.
    class LocalEvidence
      def initialize(season:, bounds:)
        @season = season
        @bounds = bounds
      end

      def pair_games(team_ids:)
        memberships = TeamGame.where(team_id: team_ids).select(:game_id)
        names = LocalEvidence.labels(team_ids).map { |name| name.to_s.strip.downcase }
        game_scope.where(id: memberships).or(game_scope.where('LOWER(TRIM(home_team_name)) IN (?) OR LOWER(TRIM(away_team_name)) IN (?)',
                                                              names, names)).order(:id)
      end

      def game_scope
        @season.games
      end

      def self.labels(team_ids)
        Team.where(id: team_ids).pluck(:school) + TeamAlias.where(team_id: team_ids).pluck(:value)
      end

      def window_games
        @season.games.where(start_time: (@bounds.start_time - 24.hours)..(@bounds.end_time + 1.day)).order(:id)
      end

      def self.participants(game)
        %w[home away].map do |side|
          membership = game.public_send("#{side}_team_game")
          membership ? [membership.team_id] : Team.matching_school_or_alias(game.public_send("#{side}_team_name")).order(:id).ids
        end
      end

      def self.duplicate_participants(game)
        %w[home away].zip(participants(game)).map do |side, ids|
          ids.present? ? ids.map(&:to_s) : ["label:#{game.public_send("#{side}_team_name").to_s.strip.downcase}"]
        end
      end

      def self.duplicate_group(games)
        { 'local_ids' => games.map(&:id), 'schedule_date' => games.first.schedule_date.iso8601,
          'disposition' => 'unresolved_duplicate_or_doubleheader' }
      end

      def duplicates
        grouped = window_games.includes(:home_team_game, :away_team_game).group_by do |game|
          [LocalEvidence.duplicate_participants(game).sort, game.schedule_date.iso8601]
        end
        grouped.values.select(&:many?).map { |games| LocalEvidence.duplicate_group(games) }
      end
    end
  end
end
