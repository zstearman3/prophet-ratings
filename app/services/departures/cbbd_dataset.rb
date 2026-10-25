# frozen_string_literal: true

module Departures
  # Source-specific JSON replay feeding the common annual input boundary.
  class CbbdDataset
    VERSION = 'draft-departures-v2'
    EXTRACTION = 'cbbd-draft-season-totals-v1'
    REPORTED_TOTALS_EXTRACTION = 'cbbd-draft-season-totals-v2'
    AUTOMATIC_EXTRACTION = 'cbbd-draft-season-totals-v4'
    SCOPES = %w[regular postseason].freeze

    def initialize(manifest:, directory:)
      @manifest = manifest
      @directory = directory
      Contract.years!(manifest)
      self.class.validate_plan(manifest)
    end

    def call
      validate_manifest
      parsed = manifest.fetch('sources').map { |source| CbbdSnapshot.new(source:, directory:, settings: manifest).call }
      build(parsed)
    end

    def self.sources(plan)
      draft = { 'id' => 'draft', 'type' => 'cbbd_draft', 'request' => { 'endpoint' => '/draft/picks', 'year' => plan['draft_year'] } }
      stats = %w[player team].flat_map { |kind| stats_sources(kind, plan.fetch('prior_season_year')) }
      [draft, *stats].map do |source|
        source.merge('url' => source_url(source.fetch('request')))
      end
    end

    def self.source_url(request)
      "https://api.collegebasketballdata.com#{request['endpoint']}?#{URI.encode_www_form(request.except('endpoint'))}"
    end

    def self.stats_sources(kind, season)
      SCOPES.map do |scope|
        { 'id' => "#{kind}-#{scope}", 'type' => "cbbd_#{kind}",
          'request' => { 'endpoint' => "/stats/#{kind}/season", 'season' => season, 'seasonType' => scope } }
      end
    end

    def self.validate_plan(plan)
      Contract.check!(plan.values_at('provider', 'schema') == ['cbbd', VERSION] && supported_extraction?(plan['extraction_version']),
                      'Unsupported departure provider/schema/extraction contract')
      AnnualDataset.validate_picks(plan.fetch('expected_picks'))
      validate_scope(plan)
      validate_limits(plan)
      validate_absences(plan)
    end

    def self.validate_scope(plan)
      if automatic?(plan)
        validate_automatic(plan)
      else
        Contract.text!(plan.fetch('scope_evidence'), 'reviewed final scope evidence')
      end
    end

    def self.supported_extraction?(version)
      version == EXTRACTION || reported_totals?('extraction_version' => version)
    end

    def self.reported_totals?(settings)
      settings['extraction_version'] == REPORTED_TOTALS_EXTRACTION || automatic?(settings)
    end

    def self.automatic?(settings)
      ['cbbd-draft-season-totals-v3', AUTOMATIC_EXTRACTION].include?(settings['extraction_version'])
    end

    def self.optional_postseason_players?(settings)
      settings['extraction_version'] == AUTOMATIC_EXTRACTION
    end

    def self.validate_automatic(plan)
      Contract.check!(plan.fetch('scope_evidence') == { 'policy' => DraftTeamSnapshot::POLICY }, 'Invalid automatic scope policy')
      Contract.check!(plan.fetch('draft_policy') == 'confirmed_retained_results', 'Invalid draft confirmation policy')
      validate_team_matches(plan.fetch('team_matches'))
    end

    def self.validate_team_matches(matches)
      Contract.check!(matches.is_a?(Array), 'Invalid prior-season team scope')
      Contract.unique!(matches.pluck('provider_team_id'), 'prior-season provider teams')
      matches.each { |entry| validate_team_match(entry) }
    end

    def self.validate_team_match(entry)
      Contract.integer!(entry.fetch('provider_team_id'), 'provider team ID', minimum: 1)
      Contract.integer!(entry.fetch('team_id'), 'team ID', minimum: 1)
      prior_id = entry['prior_team_season_id']
      Contract.integer!(prior_id, 'prior TeamSeason', minimum: 1) if prior_id
    end

    def self.validate_absences(plan)
      ids = plan.fetch('absent_postseason_team_ids', [])
      Contract.check!(ids.is_a?(Array), 'No-postseason team IDs must be an array')
      ids.each { |id| CbbdValues.id(id) }
      Contract.unique!(ids, 'no-postseason team IDs')
    end

    def self.validate_limits(plan)
      Contract.integer!(plan.fetch('max_requests'), 'max_requests', minimum: 1)
      Contract.check!(plan['max_requests'] <= 100, 'At most 100 requests')
      Contract.integer!(plan.fetch('retries'), 'retries')
      Contract.check!(plan['retries'] <= 5, 'At most 5 retries')
    end

    private

    attr_reader :manifest, :directory

    def validate_manifest
      sources = manifest.fetch('sources')
      expected = self.class.sources(manifest)
      Contract.check!(sources.pluck('id').sort == expected.pluck('id').sort, 'Require exactly five logical sources')
      validate_ledger(sources)
    end

    def validate_ledger(sources)
      validator = self.class
      captures = validator.capture_index(manifest, directory)
      validator.validate_selected(sources, captures)
    end

    public_class_method def self.capture_index(manifest, directory)
      captures = manifest.fetch('captures')
      validate_capture_count(captures, manifest.fetch('max_requests'))
      validate_capture_files(captures, sources(manifest).pluck('request'), directory)
      captures.index_by { |capture| capture.fetch('id') }
    end

    public_class_method def self.validate_capture_files(captures, requests, directory)
      captures.each { |capture| CbbdSnapshot.validate_ledger(capture, requests, directory) }
    end

    public_class_method def self.validate_capture_count(captures, limit)
      Contract.unique!(captures.pluck('id'), 'capture ledger IDs')
      Contract.check!(captures.size <= limit, 'Capture ledger exceeds request budget')
    end

    public_class_method def self.validate_selected_source(source, capture)
      fields = %w[request snapshot_kind snapshot_location snapshot_sha256 http_status captured_at observed_at sanitized]
      Contract.check!(capture.present? && source.slice(*fields) == capture.slice(*fields), 'Selected capture ledger mismatch')
    end

    public_class_method def self.validate_selected(sources, captures)
      sources.each do |source|
        id = source['selected_capture_id']
        if id
          validate_selected_source(source, captures[id])
        else
          Contract.check!(source['failure'].present? && !source.key?('snapshot_location'), 'Missing selected capture ledger reference')
        end
      end
    end

    def build(parsed)
      facts = manifest.except('dataset_revision').merge(normalized(parsed))
      facts['production_warnings'] = CbbdProduction.warnings(facts.fetch('production')) if self.class.reported_totals?(manifest)
      facts.merge('dataset_revision' => Contract.digest(facts))
    end

    def normalized(parsed)
      production = CbbdProduction.new(parsed:, settings: manifest).call
      { 'selections' => selections(parsed), 'production' => production, 'failures' => parsed.select { |source| source['failure'] } }
    rescue ArgumentError, KeyError => error
      { 'selections' => safe_selections(parsed), 'production' => [], 'failures' => self.class.normalization_failures(parsed, error) }
    end

    public_class_method def self.normalization_failures(parsed, error)
      parsed.select { |source| source['failure'] } + [{ 'id' => 'normalization', 'failure' => error.message }]
    end

    def safe_selections(parsed)
      selections(parsed)
    rescue ArgumentError, KeyError
      []
    end

    def selections(parsed)
      rows = parsed.find { |source| source['id'] == 'draft' }&.fetch('rows', []) || []
      CbbdSelections.new(rows, manifest).call
    end
  end
end
