# frozen_string_literal: true

module Ingestion
  # CBBD operational limits have no production defaults; selecting a provider is explicit.
  class GameSyncPolicy
    attr_reader :provider, :options

    def initialize(provider = nil, options = {})
      @provider = provider.presence || ENV.fetch('GAME_SYNC_PROVIDER', 'sports_reference')
      raise ArgumentError, 'Unsupported game sync provider' unless %w[sports_reference cbbd].include?(@provider)

      @options = options
      configure_cbbd if @provider == 'cbbd'
    end

    def scope
      if provider == 'sports_reference'
        { provider:, contract_version: GameObservation::VERSION, semantic_profile: 'sports-reference-legacy-v1',
          adapter_revision: 'sports-reference-bridge-v1' }
      else
        { provider:, contract_version: CanonicalObservation::FORMAT, semantic_profile: CanonicalObservation::SEMANTIC_PROFILE,
          adapter_revision: Cbbd::ImportObservation::REVISION }
      end
    end

    def self.valid_retry_limit?(value)
      value.is_a?(Integer) && value.between?(0, 5)
    end

    private

    def configure_cbbd
      return if options[:prepared_run].is_a?(CbbdReviewRun)

      @options = cbbd_options.merge(options)
      validate
    end

    def cbbd_options
      { api_key: ENV.fetch('CBBD_API_KEY', nil), capture_directory: ENV.fetch('CBBD_CAPTURE_DIRECTORY', nil),
        max_requests: integer_env('CBBD_MAX_REQUESTS'), retries: integer_env('CBBD_RETRIES') }
    end

    def integer_env(key)
      value = ENV.fetch(key, nil)
      Integer(value, 10) if value
    rescue ArgumentError
      raise ArgumentError, "#{key} must be an integer"
    end

    def validate
      limits = options
      maximum = limits[:max_requests]
      raise ArgumentError, 'CBBD requires an explicit positive max_requests' unless maximum.is_a?(Integer) && maximum.positive?
      raise ArgumentError, 'CBBD requires explicit retries between 0 and 5' unless self.class.valid_retry_limit?(limits[:retries])

      validate_storage
    end

    def validate_storage
      raise ArgumentError, 'CBBD requires a private capture_directory' if options[:capture_directory].to_s.strip.empty?
      raise ArgumentError, 'CBBD_API_KEY is required' if options[:api_key].to_s.strip.empty?
    end
  end
end
