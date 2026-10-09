# frozen_string_literal: true

module ProphetRatings
  class TeamRatingSnapshotService
    def initialize(season: Season.current, as_of: Time.current, ratings_config_version: nil)
      @ratings_config_version = RatingsConfigVersion.resolve(ratings_config_version)
      @ratings_config_version.settings
      @season = season
      @as_of = as_of
    end

    def call
      # A savepoint also protects callers that rescue a mismatch inside their own transaction.
      TeamRatingSnapshot.transaction(requires_new: true) do
        ratings_config_version = @ratings_config_version

        TeamSeason.where(season: @season).find_each do |team_season|
          team_season.validate_model_inputs(ratings_config_version)
          unless team_season.ratings_config_version_id == ratings_config_version.id
            raise ArgumentError, 'Live ratings lack selected model provenance; calculate ratings before snapshot publication'
          end

          TeamRatingSnapshot.find_or_initialize_by(
            team_id: team_season.team_id,
            season_id: @season.id,
            team_season_id: team_season.id,
            snapshot_date: @as_of,
            ratings_config_version:
          ).tap do |snapshot|
            snapshot.rating = team_season.rating
            snapshot.adj_offensive_efficiency = team_season.adj_offensive_efficiency
            snapshot.adj_defensive_efficiency = team_season.adj_defensive_efficiency
            snapshot.adj_pace = team_season.adj_pace

            # All other adjusted stats into stats column
            snapshot.stats = team_season.attributes.slice(
              *TeamRatingSnapshot::STORED_STATS,
              *TeamRatingSnapshot::STORED_RANKS
            )

            self.class.capture_provenance(snapshot, team_season, ratings_config_version)

            snapshot.save!
          end
        end
      end
    end

    def self.capture_provenance(snapshot, team_season, ratings_config_version)
      prior = PreseasonPrior.find_by(team_season:, ratings_config_version:)
      return unless prior

      unless prior.outputs.all? { |stat, value| team_season.public_send(stat) == value }
        raise ArgumentError, 'Preseason values differ from this captured model; rerun the preseason calculator for this bundle'
      end

      snapshot.stats['preseason_prior'] = prior.attributes.slice('id', 'inputs', 'outputs', 'created_at')
    end
  end
end
