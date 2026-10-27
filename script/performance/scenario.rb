# frozen_string_literal: true

module OffseasonPerformance
  # Describes the existing route, expected output and ticket limit for one measured phase.
  class Scenario
    GETS = %w[dashboard readiness departures preseason cbbd].freeze
    QUEUES = %w[preview publish schedule].freeze
    NAMES = (GETS + %w[status compare] + QUEUES + %w[solver mixed departure_normalization departure_validation]).freeze
    MARKERS = { 'dashboard' => 'Offseason', 'readiness' => 'Offseason readiness', 'departures' => 'Pick 60',
                'preseason' => 'proposed-preseason-ratings', 'cbbd' => 'CBBD' }.freeze
    attr_reader :name, :phase, :fixture

    def initialize(name, phase, fixture)
      raise 'Unknown scenario' unless NAMES.include?(name)

      @name = name
      @phase = phase
      @fixture = fixture
    end

    def get?
      GETS.include?(@name)
    end

    def publish?
      @name == 'publish'
    end

    def solver?
      @name == 'solver'
    end

    def expected_status
      { 'preview' => 'review', 'publish' => 'published' }.fetch(@name)
    end

    def queued?
      QUEUES.include?(@name)
    end

    def comparison?
      @name == 'compare'
    end

    def concurrent?
      @phase == 'concurrent'
    end

    def limit
      return Float::INFINITY if comparison?

      concurrent? ? 2 : 1
    end

    def http_method
      get? || %w[status mixed].include?(@name) ? Net::HTTP::Get : Net::HTTP::Post
    end

    def path(publication)
      paths = Scenario.paths(@fixture, publication)
      season = @fixture.fetch(@name == 'schedule' ? 'schedule_season_id' : 'season_id')
      "#{paths.fetch(@name)}?season_id=#{season}"
    end

    def self.paths(fixture, publication)
      preseason = "/admin/preseason_publications/#{fixture['publication_id']}"
      cbbd = "/admin/cbbd_review_runs/#{fixture['cbbd_id']}"
      { 'dashboard' => '/admin/offseason_setup', 'readiness' => '/admin/offseason_readiness_reviews',
        'departures' => "/admin/departure_batches/#{fixture['departure_id']}", 'preseason' => preseason,
        'status' => "#{preseason}/progress", 'mixed' => "#{preseason}/progress", 'preview' => '/admin/preseason_publications',
        'publish' => "/admin/preseason_publications/#{publication&.id}/publish", 'cbbd' => cbbd,
        'compare' => "#{cbbd}/compare", 'schedule' => '/admin/schedule_refresh_runs' }
    end

    def valid_response?(response)
      return false unless response.code.to_i == (http_method == Net::HTTP::Get ? 200 : 302)

      valid_body?(response.body)
    end

    def valid_body?(body)
      return body.include?(MARKERS.fetch(@name)) if MARKERS.key?(@name)
      return JSON.parse(body).keys.sort == %w[status updated_at] if %w[status mixed].include?(@name)

      true
    end

    def form(publication)
      case @name
      when 'preview' then { 'mode' => 'initialize' }
      when 'publish' then { 'fingerprint' => publication.fingerprint, 'acknowledge' => '1' }
      when 'schedule' then schedule_form
      else {}
      end
    end

    def schedule_form
      date = @fixture.fetch('schedule_date')
      { 'refresh[provider]' => 'cbbd', 'refresh[start_date]' => date, 'refresh[end_date]' => date,
        'refresh[max_requests]' => '20', 'refresh[retries]' => '0', 'refresh[mode]' => 'historical', 'refresh[rescan]' => 'true' }
    end
  end
end
