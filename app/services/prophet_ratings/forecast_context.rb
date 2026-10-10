# frozen_string_literal: true

module ProphetRatings
  # Captures effective inputs before calculation; replay never follows mutable source records.
  class ForecastContext
    RATING_FIELDS = %w[adj_offensive_efficiency adj_defensive_efficiency adj_pace].freeze
    STATS_FIELDS = %w[offensive_efficiency_volatility defensive_efficiency_volatility pace_volatility
                      home_offense_boost home_defense_boost].freeze
    # Only the persisted season anchors and fallback deviations needed for replay.
    SeasonInputs = Struct.new(:average_efficiency, :average_pace, :efficiency_std_deviation, :pace_std_deviation, keyword_init: true)

    def self.capture(game, snapshots, version)
      config = version.settings
      season = game.season
      {
        'contract_version' => 1,
        'model_version_id' => version.id,
        'model_config' => version.config,
        'season_id' => game.season_id,
        'season_source' => season.attributes.slice('id', 'updated_at', 'average_efficiency', 'average_pace',
                                                   'efficiency_std_deviation', 'pace_std_deviation'),
        'season' => season_inputs(season, config),
        'venue' => game.attributes.slice('venue_type', 'venue_confidence', 'venue_source', 'venue_name', 'neutral'),
        'snapshots' => snapshots.map { |snapshot| snapshot_inputs(snapshot) },
        'upset_modifier' => 1.0
      }
    end

    def self.season_inputs(season, config)
      {
        'average_efficiency' => (season.average_efficiency || config.dig(:defaults, :season_defaults, :average_efficiency)).to_f,
        'average_pace' => (season.average_pace || config.dig(:defaults, :season_defaults, :average_pace)).to_f,
        'efficiency_std_deviation' => (season.efficiency_std_deviation || config.dig(:baseline_volatility, :efficiency_volatility)).to_f,
        'pace_std_deviation' => (season.pace_std_deviation || config.dig(:baseline_volatility, :pace_volatility)).to_f
      }
    end

    def self.snapshot_inputs(snapshot)
      {
        'source' => snapshot.attributes.slice('id', 'team_id', 'team_season_id', 'snapshot_date', 'created_at', 'updated_at')
                            .merge(snapshot.stats.slice('reconstruction')),
        'ratings' => numerical_fields(snapshot, RATING_FIELDS),
        'stats' => numerical_fields(snapshot, STATS_FIELDS),
        'school' => snapshot.team.school
      }
    end

    def self.numerical_fields(snapshot, fields)
      fields.index_with { |field| snapshot.public_send(field)&.to_f }
    end

    def initialize(data)
      @data = data.deep_stringify_keys
    end

    def predictor
      home, away = snapshots
      GamePredictor.new(home_rating_snapshot: home, away_rating_snapshot: away,
                        season: SeasonInputs.new(**@data.fetch('season').symbolize_keys),
                        ratings_config_version: version, upset_modifier: @data.fetch('upset_modifier'),
                        venue: { type: @data.dig('venue', 'venue_type'), confidence: @data.dig('venue', 'venue_confidence') })
    end

    def margin_std_deviation
      return Math.sqrt(moments.margin_variance) if shared_pace?

      combined_efficiency_sd * calculation_inputs.dig('means', 'pace') / 100.0
    end

    def total_std_deviation
      return Math.sqrt(moments.total_variance) if shared_pace?

      combined_efficiency_sd * (calculation_inputs.dig('means', 'pace')**2) / 10_000.0
    end

    private

    def calculation_inputs
      @calculation_inputs ||= predictor.calculation_inputs
    end

    def moments
      ScoreMoments.new(means: calculation_inputs.fetch('means').symbolize_keys,
                       deviations: calculation_inputs.fetch('deviations').symbolize_keys)
    end

    def combined_efficiency_sd
      Math.sqrt(calculation_inputs.fetch('deviations').slice('home', 'away').values.sum { |value| value**2 })
    end

    def shared_pace?
      @data.dig('model_config', 'prediction', 'uncertainty_model') == 'shared_pace_v1'
    end

    def version
      @version ||= RatingsConfigVersion.instantiate('id' => @data.fetch('model_version_id'),
                                                    'name' => @data.dig('model_config', 'bundle_name'),
                                                    'config' => @data.fetch('model_config'))
    end

    def snapshot_from(inputs)
      ratings, stats, source, school = inputs.values_at('ratings', 'stats', 'source', 'school')
      TeamRatingSnapshot.new(**ratings, stats:, ratings_config_version: version,
                                        team: Team.new(id: source.fetch('team_id'), school:))
    end

    def snapshots
      @data.fetch('snapshots').map do |inputs|
        snapshot_from(inputs)
      end
    end
  end
end
