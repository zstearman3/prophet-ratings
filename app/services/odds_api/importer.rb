# frozen_string_literal: true

module OddsApi
  class Importer
    def initialize(api_response)
      @response = api_response
    end

    def call
      @response.each do |game_data|
        game = find_game(game_data)

        odds = OddsApi::ConsensusCalculator.new(game_data).consensus
        GameOdd.create!(odds.merge(game:))

        game_data.each do |_bookmaker_data|
          BookmakerOdds.create!(
            game:,
            bookmaker:,
            fetched_at:,
            market:,
            team_name:,
            team_side:,
            value:,
            odds:
          )
        end
      end
    end

    private

    def find_game(game_data)
      home_team = TeamMatcher.new.match(game_data[:home_team])
      away_team = TeamMatcher.new.match(game_data[:away_team])
      start_time = Time.zone.parse(game_data[:commence_time])

      Game
        .joins(:home_team, :away_team)
        .where(home_teams: { id: home_team.id }, away_teams: { id: away_team.id })
        .where(start_time: start_time.all_day)
        .first!
    end
  end
end
