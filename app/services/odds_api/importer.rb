# frozen_string_literal: true

module OddsApi
  class Importer
    def initialize(api_response)
      @response = api_response
    end

    def call
      Array(@response).each do |game_data|
        import_game(game_data)
      end
    end

    private

    def import_game(game_data)
      home_team = team_matcher.match(value_for(game_data, :home_team))
      away_team = team_matcher.match(value_for(game_data, :away_team))
      start_time = Time.zone.parse(value_for(game_data, :commence_time))
      game = find_game(home_team:, away_team:, start_time:)

      import_game_odd(game:, home_team:, away_team:, game_data:)
      import_bookmaker_odds(
        game:,
        bookmakers: value_for(game_data, :bookmakers),
        home_team_name: value_for(game_data, :home_team),
        away_team_name: value_for(game_data, :away_team)
      )
    end

    def find_game(home_team:, away_team:, start_time:)
      raise ActiveRecord::RecordNotFound, 'Could not match game teams from odds payload' unless home_team && away_team

      Game
        .where(start_time: start_time.all_day)
        .includes(:home_team_game, :away_team_game)
        .detect do |game|
          game.home_team_game&.team_id == home_team.id &&
            game.away_team_game&.team_id == away_team.id
        end || raise(ActiveRecord::RecordNotFound, 'Could not find game for odds payload')
    end

    def import_game_odd(game:, home_team:, away_team:, game_data:)
      odds = OddsApi::ConsensusCalculator.new(
        bookmakers: value_for(game_data, :bookmakers),
        home_team:,
        away_team:
      ).consensus

      game_odd = GameOdd.find_or_initialize_by(game:)
      game_odd.assign_attributes(odds)
      game_odd.save!
    end

    def import_bookmaker_odds(game:, bookmakers:, home_team_name:, away_team_name:)
      Array(bookmakers).each do |bookmaker_data|
        import_bookmaker_markets(
          game:,
          bookmaker_data:,
          home_team_name:,
          away_team_name:
        )
      end
    end

    def import_bookmaker_markets(game:, bookmaker_data:, home_team_name:, away_team_name:)
      Array(value_for(bookmaker_data, :markets)).each do |market_data|
        Array(value_for(market_data, :outcomes)).each do |outcome|
          bookmaker_odd = BookmakerOdd.find_or_initialize_by(
            game:,
            bookmaker: bookmaker_name(bookmaker_data),
            market: value_for(market_data, :key),
            team_name: value_for(outcome, :name)
          )

          bookmaker_odd.assign_attributes(
            fetched_at: fetched_at_for(bookmaker_data, market_data),
            team_side: team_side_for(
              market_key: value_for(market_data, :key),
              outcome_name: value_for(outcome, :name),
              home_team_name:,
              away_team_name:
            ),
            value: market_value(value_for(market_data, :key), outcome),
            odds: value_for(outcome, :price)
          )
          bookmaker_odd.save!
        end
      end
    end

    def fetched_at_for(bookmaker_data, market_data)
      Time.zone.parse(value_for(market_data, :last_update) || value_for(bookmaker_data, :last_update))
    end

    def team_side_for(market_key:, outcome_name:, home_team_name:, away_team_name:)
      case market_key
      when 'totals'
        return 'over' if outcome_name == 'Over'
        return 'under' if outcome_name == 'Under'
      else
        return 'home' if outcome_name == home_team_name
        return 'away' if outcome_name == away_team_name
      end

      nil
    end

    def market_value(market_key, outcome)
      return unless %w[spreads totals].include?(market_key)

      value_for(outcome, :point)
    end

    def bookmaker_name(bookmaker_data)
      value_for(bookmaker_data, :title) || value_for(bookmaker_data, :key)
    end

    def team_matcher
      @team_matcher ||= TeamMatcher.new
    end

    def value_for(hash, key)
      hash[key] || hash[key.to_s]
    end
  end
end
