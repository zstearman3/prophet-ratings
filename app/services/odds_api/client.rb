# frozen_string_literal: true

module OddsApi
  class Client
    BASE_URL = 'https://api.the-odds-api.com/v4/sports/basketball_ncaab/odds'

    def initialize
      @api_key = ENV.fetch('ODDS_API_KEY')
    end

    def fetch_odds
      params = {
        apiKey: @api_key,
        regions: 'us',
        markets: 'spreads,totals,h2h', # spreads = line, totals = over/under, h2h = moneyline
        oddsFormat: 'american',
        dateFormat: 'iso'
      }

      uri = URI(BASE_URL)
      uri.query = URI.encode_www_form(params)

      response = Net::HTTP.get_response(uri)
      raise "Error fetching odds: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body, symbolize_names: true)
    end
  end
end
