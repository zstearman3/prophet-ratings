# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OddsApi::Client, type: :service do
  describe '#fetch_odds' do
    subject(:fetch_odds) { described_class.new.fetch_odds }

    let(:response) do
      Net::HTTPOK.new('1.1', '200', 'OK').tap do |http_response|
        allow(http_response).to receive(:body).and_return(response_body)
      end
    end
    let(:response_body) do
      [
        {
          id: 'game-1',
          home_team: 'UAB Blazers',
          away_team: 'North Texas Mean Green'
        }
      ].to_json
    end

    before do
      allow(ENV).to receive(:fetch).with('ODDS_API_KEY').and_return('test-api-key')
      allow(Net::HTTP).to receive(:get_response).and_return(response)
    end

    it 'requests NCAAB odds with the configured API key and markets' do
      fetch_odds

      expect(Net::HTTP).to have_received(:get_response) do |uri|
        expect(uri.to_s).to start_with('https://api.the-odds-api.com/v4/sports/basketball_ncaab/odds?')
        expect(URI.decode_www_form(uri.query).to_h).to include(
          'apiKey' => 'test-api-key',
          'regions' => 'us',
          'markets' => 'spreads,totals,h2h',
          'oddsFormat' => 'american',
          'dateFormat' => 'iso'
        )
      end
    end

    it 'returns symbolized JSON payloads' do
      expect(fetch_odds).to eq(
        [
          {
            id: 'game-1',
            home_team: 'UAB Blazers',
            away_team: 'North Texas Mean Green'
          }
        ]
      )
    end

    context 'when the API returns a non-success response' do
      let(:response) { Net::HTTPTooManyRequests.new('1.1', '429', 'Too Many Requests') }

      it 'raises an error with the response code' do
        expect { fetch_odds }.to raise_error(RuntimeError, 'Error fetching odds: 429')
      end
    end
  end
end
