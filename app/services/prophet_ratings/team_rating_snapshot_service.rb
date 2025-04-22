# frozen_string_literal: true

module ProphetRatings
  class TeamRatingSnapshotService
    def initialize(season: Season.current, as_of: Time.current, config_bundle_name: "default")
      @season = season
      @as_of = as_of
      @config_bundle_name = config_bundle_name
    end

    def call
      ProphetRatings::OverallRatingsCalculator.new(@season).calculate_season_ratings(as_of: @as_of)

      TeamSeason.where(season: @season).find_each do |team_season|
        TeamRatingSnapshot.find_or_initialize_by(
          team_id: team_season.team_id,
          season_id: @season.id,
          team_season_id: team_season.id,
          snapshot_date: @as_of,
          config_bundle_name: @config_bundle_name
        ).tap do |snapshot|
          snapshot.rating = team_season.rating
          snapshot.adj_offensive_efficiency = team_season.adj_offensive_efficiency
          snapshot.adj_defensive_efficiency = team_season.adj_defensive_efficiency
          snapshot.adj_pace = team_season.adj_pace
  
          # All other adjusted stats into stats column
          snapshot.stats = team_season.attributes.slice(
            *TeamRatingSnapshot::STORED_STATS
          )
  
          snapshot.save!
        end
      end
    end
  end
end
