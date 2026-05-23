# frozen_string_literal: true

module OddsApi
  class SyncService
    Result = Struct.new(:fetched_count, :imported_count, :failures, keyword_init: true) do
      def failed_count
        failures.size
      end
    end

    def self.call(client: OddsApi::Client.new)
      new(client:).call
    end

    def initialize(client: OddsApi::Client.new, logger: Rails.logger)
      @client = client
      @logger = logger
    end

    def call
      odds_payloads = Array(client.fetch_odds)
      result = Result.new(fetched_count: odds_payloads.size, imported_count: 0, failures: [])

      odds_payloads.each do |game_data|
        import_game(game_data, result)
      end

      result
    end

    private

    attr_reader :client, :logger

    def import_game(game_data, result)
      OddsApi::Importer.new([game_data]).call
      result.imported_count += 1
    rescue ActiveRecord::RecordNotFound, ArgumentError => e
      failure = failure_for(game_data, e)
      result.failures << failure
      logger.warn("Odds API sync skipped game: #{failure.inspect}")
    end

    def failure_for(game_data, error)
      {
        odds_api_game_id: value_for(game_data, :id),
        home_team: value_for(game_data, :home_team),
        away_team: value_for(game_data, :away_team),
        commence_time: value_for(game_data, :commence_time),
        error_class: error.class.name,
        message: error.message
      }
    end

    def value_for(hash, key)
      hash[key] || hash[key.to_s]
    end
  end
end
