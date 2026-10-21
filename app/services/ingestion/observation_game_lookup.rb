# frozen_string_literal: true

module Ingestion
  # Bootstrap is deliberately broader than uniqueness: every plausible candidate must be reviewed when ambiguous.
  class ObservationGameLookup
    def initialize(resolution)
      @resolution = resolution
      @data = resolution.observation.data
    end

    def call
      candidates = (url_games + date_games.select { |candidate| participant_match?(candidate) }).uniq(&:id)
      validate_candidates(candidates)
      candidates.first
    end

    def self.date_games(date)
      legacy_day = Time.zone.local(date.year, date.month, date.day).all_day
      Game.on_schedule_date(date).or(Game.where(start_time: legacy_day))
    end

    private

    def url_games
      url = @data[:source_url]
      return [] if @resolution.observation.schedule_projection? || url.to_s.include?('/cbb/boxscores/index.cgi')

      Game.where(url:).to_a
    end

    def validate_candidates(candidates)
      return unless candidates.size > 1 || candidates.any? { |candidate| candidate.season_id != @resolution.season.id }

      raise ObservationResolution::Held.new('ambiguous', 'multiple_or_cross_season_candidates')
    end

    def date_games
      self.class.date_games(Date.iso8601(@data[:schedule_date]))
    end

    def projection_alias_match?(names)
      return false unless @resolution.observation.schedule_projection?

      names.all? { |name| Team.matching_school_or_alias(name).exists?(id: @resolution.teams) }
    end

    def participant_match?(candidate)
      values = candidate.attributes.values_at('home_team_name', 'away_team_name')
      ids = TeamGame.where(game: candidate).pluck(:team_id).sort
      ids == @resolution.teams.map(&:id).sort || values == @resolution.incoming_names || projection_alias_match?(values)
    end
  end
end
