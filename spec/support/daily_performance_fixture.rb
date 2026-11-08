# frozen_string_literal: true

module DailyPerformanceFixture
  def build_daily_forecast(probability: 0.3, ratings_config_version: nil)
    season = create(:season, :current, average_efficiency: 100, average_pace: 70)
    version = ratings_config_version || create(:ratings_config_version, current: true)
    game = create(:game, season:, start_time: 4.hours.from_now, status: :scheduled,
                         home_team_score: nil, away_team_score: nil)
    teams = Array.new(2) { create(:team_season, season:) }
    teams.each_with_index do |team, index|
      create(:team_game, game:, team: team.team, team_season: team, opponent_team_season: teams[1 - index], home: index.zero?)
    end
    snapshots = teams.map do |team|
      create(:team_rating_snapshot, :with_forecast_inputs, team_season: team, ratings_config_version: version,
                                                           snapshot_date: game.schedule_date - 1)
    end
    prediction = create(:prediction, game:, ratings_config_version: version,
                                     home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last,
                                     forecast_kind: 'pregame',
                                     calculation_context: ProphetRatings::ForecastContext.capture(game, snapshots, version),
                                     generated_at: 1.hour.ago, forecast_start_time: game.start_time,
                                     input_cutoff: game.schedule_date - 1, revision_key: 'daily-1',
                                     home_score: 70, away_score: 80, home_win_probability: probability, pace: 70)
    odds = create(:game_odd, game:, fetched_at: 10.minutes.ago, spread_point: -5,
                             spread_home_odds: -110, spread_away_odds: -110,
                             moneyline_home: -200, moneyline_away: 150,
                             total_points: 140, total_over_odds: -110, total_under_odds: -110)
    [game, prediction, odds, version]
  end
end

RSpec.configure { |config| config.include DailyPerformanceFixture }
