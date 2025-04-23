# app/services/prophet_ratings/game_weighting_service.rb
module ProphetRatings
  class GameWeightingService
    def initialize(game:, season: Season.current, as_of: nil)
      @game = game
      @season = season
      @as_of = as_of || [Time.current.to_date, season.end_date].min
    end

    def call
      # might expand scope of this later
      recency_weight
    end

    private

    def recency_weight
      decay_days = config[:recency_decay_days]
      min_weight = config[:min_recency_weight]
      days_ago = (@as_of.to_date - @game.game.start_time.to_date).to_i
      [1.0 - ((days_ago / decay_days) * (1 - min_weight)), min_weight].max
    end

    def config
      @config ||= Rails.application.config_for(:ratings).deep_symbolize_keys[:weighting]
    end
  end
end
