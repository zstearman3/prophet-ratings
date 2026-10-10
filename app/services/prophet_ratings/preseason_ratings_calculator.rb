# frozen_string_literal: true

module ProphetRatings
  class PreseasonRatingsCalculator
    def initialize(season = Season.current, ratings_config_version: nil)
      @ratings_config_version = RatingsConfigVersion.resolve(ratings_config_version)
      @config = @ratings_config_version.settings
      @season = season
      @previous_season = Season.find_by(year: @season.year - 1)
    end

    def call
      @season.with_lock do
        version = @ratings_config_version
        @season.rating_team_seasons.includes(:team_offseason_profile).find_each do |team_season|
          prior = captured_prior(team_season, version)
          team_season.update!(prior.outputs.merge(preseason_prior: prior))
        end
      end
    end

    def captured_prior(team_season, version)
      PreseasonPrior.find_by(team_season:, ratings_config_version: version) || begin
        inputs = capture_inputs(team_season)
        PreseasonPrior.create!(team_season:, ratings_config_version: version, inputs:,
                               outputs: PreseasonPriorFormula.new(inputs, version.config).call)
      end
    end

    def capture_inputs(team_season)
      previous = @previous_season&.team_seasons&.find_by(team_id: team_season.team_id)
      profile = team_season.team_offseason_profile
      serializer = self.class
      {
        contract: 'preseason-v1', configuration: @config,
        previous_season: serializer.source_identity(@previous_season), previous_team_season: serializer.source_identity(previous),
        profile: serializer.source_identity(profile),
        previous_values: serializer.previous_values(previous),
        baselines: PreseasonPriorFormula::STATS.index_with { |stat| average_for_stat(stat) },
        profile_values: serializer.normalized_profile(profile)
      }
    end

    def self.previous_values(previous)
      PreseasonPriorFormula::STATS.index_with { |stat| previous&.public_send(stat) }
    end

    def self.source_identity(record)
      return unless record

      { id: record.id, updated_at: record.updated_at.iso8601(6), attributes: record.attributes.transform_values do |value|
        value.is_a?(Float) && !value.finite? ? value.to_s : value
      end }
    end

    def self.normalized_profile(profile)
      return {} unless profile

      values = profile_attributes(profile)
      values['recruiting_score'] = valid_recruiting_score(values['recruiting_score'])
      values['returning_minutes_pct'] = valid_returning_fraction(values['returning_minutes_pct'])
      values
    end

    def self.profile_attributes(profile)
      profile.attributes.slice('recruiting_score', 'returning_minutes_pct', 'manual_adjustment')
             .transform_values { |value| value&.finite? ? value : nil }
    end

    def self.valid_recruiting_score(value)
      value if value && value >= 0
    end

    def self.valid_returning_fraction(value)
      value if value && (0.0..1.0).cover?(value)
    end

    def fallback_efficiency
      @config.fetch(:preseason).fetch(:fallback_efficiency)
    end

    def average_for_stat(stat)
      case stat
      when 'adj_offensive_efficiency'
        @previous_season&.avg_adj_offensive_efficiency || @previous_season&.average_efficiency ||
          fallback_efficiency
      when 'adj_defensive_efficiency'
        @previous_season&.avg_adj_defensive_efficiency || @previous_season&.average_efficiency ||
          fallback_efficiency
      when 'adj_pace'
        @previous_season&.average_pace || @config.dig(:preseason, :fallback_pace)
      end
    end
    private :captured_prior, :capture_inputs, :fallback_efficiency, :average_for_stat
  end
end
