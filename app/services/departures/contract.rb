# frozen_string_literal: true

require 'digest'

module Departures
  # File-only acquisition contract. Database publication belongs to a separate story.
  module Contract
    VERSION = 'draft-departures-v1'
    EXTRACTION = 'nba-results-sidearm-totals-v1'
    SCOPE = 'overall_season_including_postseason_excluding_exhibitions'
    STATUSES = %w[eligible_prior_season verified_no_college verified_nonparticipant outside_prior_season
                  unknown_participation unknown_production unresolved_identity conflicting_evidence].freeze
    RESOLVED = %w[eligible_prior_season verified_no_college verified_nonparticipant outside_prior_season].freeze

    def self.check!(condition, message)
      raise ArgumentError, message unless condition

      condition
    end

    def self.text!(value, name)
      check!(value.is_a?(String) && value.strip.present?, "Missing #{name}")
      value
    end

    def self.integer!(value, name, minimum: 0)
      check!(value.is_a?(Integer) && value >= minimum, "Invalid #{name}: expected integer >= #{minimum}")
      value
    end

    def self.years!(settings)
      draft = integer!(settings.fetch('draft_year'), 'draft_year', minimum: 2)
      prior = integer!(settings.fetch('prior_season_year'), 'prior_season_year', minimum: 2)
      target = integer!(settings.fetch('target_year'), 'target_year', minimum: 3)
      check!(draft < 9999 && prior == draft && target == draft + 1,
             'Draft Y requires prior_season_year Y and target_year Y+1, within four digits')
    end

    def self.url!(value)
      uri = URI.parse(text!(value, 'source URL'))
      check!(uri.scheme == 'https' && uri.host.present? && !uri.userinfo && !uri.fragment, 'Require an absolute HTTPS URL')
      value
    end

    # Sorted keys make identity independent of JSON formatting, never of evidence bytes.
    def self.canonical(value)
      converter = method(:canonical)
      case value
      when Hash then value.sort.to_h.transform_values(&converter)
      when Array then value.map(&converter)
      else value
      end
    end

    def self.hash(value)
      Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
    end

    def self.write(path, value)
      bytes = "#{JSON.pretty_generate(canonical(value))}\n"
      write_bytes(path, bytes)
    end

    def self.write_bytes(path, bytes)
      return if File.exist?(path) && File.binread(path) == bytes.b

      File.open(path, File::WRONLY | File::CREAT | File::EXCL) { |file| file.binmode.write(bytes) }
    end

    def self.unique!(values, name)
      check!(values.uniq.size == values.size, "Duplicate #{name}")
    end
  end
end
