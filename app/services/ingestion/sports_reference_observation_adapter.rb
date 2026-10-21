# frozen_string_literal: true

module Ingestion
  # Translation only; historical counts are not certified official team totals.
  class SportsReferenceObservationAdapter
    def initialize(row, season: nil)
      @row = row
      @date = Game.schedule_date_for(Game.schedule_time_for(row.fetch(:date)))
      @season = season
    end

    def call
      GameObservation.new(metadata.merge(home: side(:home), away: side(:away), venue:,
                                         raw_payload: row.as_json, payload_digest: Digest::SHA256.hexdigest(row.to_json)))
    end

    private

    attr_reader :row, :date

    def season
      @season ||= Season.find_by('start_date <= ? AND end_date >= ?', date, date)
    end

    def metadata
      url = row[:url]
      adapter = self.class
      { contract_version: GameObservation::VERSION, semantic_profile: 'sports-reference-legacy-v1', provider: 'sports_reference',
        external_game_id: adapter.stable_url(url), source_url: url, season_year: season&.year, schedule_date: date.iso8601,
        start_time: row[:time_precision] == 'instant' ? Game.schedule_time_for(row[:date]).iso8601 : nil,
        captured_at: Time.current.iso8601(6), source_updated_at: row[:source_updated_at],
        adapter_revision: 'sports-reference-bridge-v1', duration_minutes: duration_minutes }
        .merge(completion_metadata)
    end

    def completion_metadata
      completed = row[:source_completed] == true
      { source_status: row[:source_status] || (completed ? 'final' : 'scheduled'), source_completed: completed,
        completion_evidence: row[:source_completion_evidence] }
    end

    def side(label)
      { name: row[:"#{label}_team"], score: row[:"#{label}_team_score"],
        stats: row.fetch(:"#{label}_team_stats", {}).to_h.symbolize_keys }
    end

    def venue
      attrs = row.slice(:venue_type, :venue_source, :venue_confidence, :venue_name, :neutral)
      return attrs if attrs.any?

      location = row[:box_score_location].to_s.strip
      location.present? ? location_venue(location) : {}
    end

    def location_venue(name)
      team = home_team
      attrs = { venue_name: name, venue_source: 'sports_reference_box_score_header' }
      return attrs unless team && self.class.home_location?(team, name)

      attrs.merge(venue_type: 'home', venue_confidence: 'confirmed', neutral: false)
    end

    def home_team
      Team.matching_school_or_alias(row[:home_team]).sole
    rescue ActiveRecord::RecordNotFound, ActiveRecord::SoleRecordExceeded
      nil
    end

    def duration_minutes
      self.class.duration(row.fetch(:home_team_stats, {}).to_h.symbolize_keys[:minutes])
    end

    class << self
      def stable_url(value)
        url = value.to_s
        url if url.present? && url.exclude?('/cbb/boxscores/index.cgi')
      end

      def duration(value)
        return unless value.to_s.match?(/\A\d+\z/)

        minutes = value.to_i
        minutes / 5 if (minutes % 5).zero?
      end

      def home_location?(team, name)
        venue = team.home_venue
        location = team.location
        (venue.present? && name.casecmp(venue.strip).zero?) || (location.present? && name.downcase.include?(location.strip.downcase))
      end
    end
  end
end
