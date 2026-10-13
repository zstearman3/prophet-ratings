# frozen_string_literal: true

module Departures
  # Validates and replays one immutable source capture using its original bytes.
  class SourceSnapshot
    TYPES = %w[nba_results sidearm_totals evidence].freeze

    def initialize(source:, directory:, settings:)
      @source = source
      @directory = directory
      @settings = settings
      validate_configuration
    end

    def call
      return report if source['failure']

      report.merge('rows' => extract(saved_bytes))
    rescue ArgumentError, KeyError, Errno::ENOENT => error
      report.merge('failure' => error.message)
    end

    private

    attr_reader :source, :directory, :settings

    def report
      source.slice('id', 'type', 'failure')
    end

    def validate_configuration
      Contract.text!(source.fetch('id'), 'source ID')
      Contract.url!(source.fetch('url'))
      Contract.check!(TYPES.include?(source.fetch('type')), 'Unsupported source type')
      validate_draft_url if source['type'] == 'nba_results'
    end

    def validate_draft_url
      Contract.check!(source.fetch('url') == "https://www.nba.com/news/#{settings.fetch('draft_year')}-nba-draft-order",
                      'Require the official annual NBA results URL')
    end

    def saved_bytes
      validate_metadata
      bytes = File.binread(File.join(directory, source.fetch('snapshot_location')))
      Contract.check!(Digest::SHA256.hexdigest(bytes) == source.fetch('snapshot_sha256'), 'Source snapshot hash mismatch')
      bytes
    end

    def validate_metadata
      sha = source.fetch('snapshot_sha256')
      location = source.fetch('snapshot_location')
      Contract.check!(location == "#{sha}.html" && location.match?(/\A[a-f0-9]{64}\.html\z/),
                      'Invalid content-addressed snapshot location')
      validate_capture
    end

    def validate_capture
      Contract.check!(source.fetch('snapshot_kind') == 'raw_html' && source.fetch('http_status') == 200, 'Unusable HTML capture')
      %w[captured_at observed_at].each { |key| Time.iso8601(source.fetch(key)) }
      validate_as_of
    end

    def validate_as_of
      as_of = source['source_as_of']
      Contract.text!(source.fetch('source_as_of_reason'), 'source_as_of_reason') unless as_of
      Time.iso8601(as_of) if as_of
    end

    def extract(html)
      case source.fetch('type')
      when 'nba_results' then NbaResults.new(source:, html:, draft_year: settings.fetch('draft_year')).call
      when 'sidearm_totals' then SidearmTotals.new(source:, html:, prior_season_year: settings.fetch('prior_season_year')).call
      when 'evidence' then nil
      end
    end
  end
end
