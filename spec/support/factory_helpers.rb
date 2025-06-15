# frozen_string_literal: true

# spec/support/factory_helpers.rb
module FactoryHelpers
  def create_basic_two_team_game(season:, stat:, value1:, value2:)
    team1 = create(:team)
    team2 = create(:team)
    ts1 = create(:team_season, team: team1, season:)
    ts2 = create(:team_season, team: team2, season:)
    game = create(:game, season:)

    create(:team_game, game:, team: team1, team_season: ts1, opponent_team_season: ts2, stat => value1, home: true)
    create(:team_game, game:, team: team2, team_season: ts2, opponent_team_season: ts1, stat => value2, home: false)

    [ts1, ts2]
  end

  def create_three_team_round_robin(season:, stat:)
    t1 = create(:team)
    t2 = create(:team)
    t3 = create(:team)

    ts1 = create(:team_season, team: t1, season:)
    ts2 = create(:team_season, team: t2, season:)
    ts3 = create(:team_season, team: t3, season:)

    g1 = create(:game, season:, start_time: Time.zone.now.change(hour: 12, min: 0, sec: 0), home_team_name: t1.school,
                       away_team_name: t2.school)
    create(:team_game, game: g1, team: t1, team_season: ts1, opponent_team_season: ts2, stat => 0.60, home: true)
    create(:team_game, game: g1, team: t2, team_season: ts2, opponent_team_season: ts1, stat => 0.45, home: false)

    g2 = create(:game, season:, start_time: Time.zone.now.change(hour: 15, min: 0, sec: 0), home_team_name: t2.school,
                       away_team_name: t3.school)
    create(:team_game, game: g2, team: t2, team_season: ts2, opponent_team_season: ts3, stat => 0.55, home: true)
    create(:team_game, game: g2, team: t3, team_season: ts3, opponent_team_season: ts2, stat => 0.50, home: false)

    g3 = create(:game, season:, start_time: Time.zone.now.change(hour: 18, min: 0, sec: 0), home_team_name: t3.school,
                       away_team_name: t1.school)
    create(:team_game, game: g3, team: t3, team_season: ts3, opponent_team_season: ts1, stat => 0.52, home: true)
    create(:team_game, game: g3, team: t1, team_season: ts1, opponent_team_season: ts3, stat => 0.58, home: false)

    [ts1, ts2, ts3]
  end
end
