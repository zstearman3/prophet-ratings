# frozen_string_literal: true

module ProphetRatings
  class TeamRatingSnapshotService
    def initialize(season: Season.current, as_of: Time.current)
      @season = season
      @as_of = as_of
    end

    def call
      current_config = Rails.application.config_for(:ratings).deep_symbolize_keys
      ratings_config_version = RatingsConfigVersion.find_or_create_by_config(current_config)

      TeamSeason.where(season: @season).find_each do |team_season|
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
            *TeamRatingSnapshot::STORED_RANKS,
          )

          snapshot.save!
        end
      end
    end
  end
end
