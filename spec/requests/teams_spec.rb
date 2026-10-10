# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Teams' do
  describe 'GET /teams/:slug' do
    let(:snapshot_stats) do
      {
        adj_effective_fg_percentage: 0.51,
        adj_effective_fg_percentage_allowed: 0.47,
        adj_turnover_rate: 0.16,
        adj_turnover_rate_forced: 0.18,
        adj_offensive_rebound_rate: 0.29,
        adj_defensive_rebound_rate: 0.72,
        adj_free_throw_rate: 0.24,
        adj_free_throw_rate_allowed: 0.21,
        adj_three_pt_proficiency: 0.36,
        adj_three_pt_proficiency_allowed: 0.31,
        overall_rank: 12,
        adj_offensive_efficiency_rank: 15,
        adj_defensive_efficiency_rank: 18,
        adj_pace_rank: 44,
        adj_effective_fg_percentage_rank: 20,
        adj_turnover_rate_rank: 35,
        adj_offensive_rebound_rate_rank: 28,
        adj_free_throw_rate_rank: 30,
        adj_effective_fg_percentage_allowed_rank: 24,
        adj_turnover_rate_forced_rank: 19,
        adj_defensive_rebound_rate_rank: 14,
        adj_free_throw_rate_allowed_rank: 23,
        adj_three_pt_proficiency_rank: 16,
        adj_three_pt_proficiency_allowed_rank: 21
      }
    end

    it 'keeps scheduled and final game content and links inside the scrollable table' do
      season = create(:season, :current, year: 2026, start_date: Date.new(2025, 11, 1), end_date: Date.new(2026, 4, 1))
      config = create(:ratings_config_version, name: 'v1.2-default', current: true)
      conference = create(:conference, name: 'Test Conference', abbreviation: 'TC', slug: 'tc')
      team = create(:team, school: 'Home Team', slug: 'home-team')
      opponent = create(:team, school: 'University of North Carolina at Asheville', slug: 'away-team')
      team_season = create(:team_season, team:, season:, wins: 10, losses: 5, conference_wins: 4, conference_losses: 2, rating: 25.0)
      opponent_team_season = create(:team_season, team: opponent, season:, rating: 20.0)
      create(:team_conference, team:, conference:, start_season: season)
      create(:team_conference, team: opponent, conference:, start_season: season)
      home_snapshot = create(
        :team_rating_snapshot,
        team_season:,
        team:,
        season:,
        ratings_config_version: config,
        snapshot_date: Date.current,
        rating: 25.0,
        stats: snapshot_stats
      )
      create(
        :team_rating_snapshot,
        team_season:,
        team:,
        season:,
        ratings_config_version: config,
        snapshot_date: Date.current - 1.day,
        rating: 24.5
      )
      opponent_snapshot = create(
        :team_rating_snapshot,
        team_season: opponent_team_season,
        team: opponent,
        season:,
        ratings_config_version: config,
        snapshot_date: Date.current,
        rating: 20.0
      )
      game = create(
        :game,
        season:,
        start_time: Date.current.beginning_of_day + 12.hours,
        status: :scheduled,
        home_team_name: team.school,
        away_team_name: opponent.school
      )
      create(:team_game, game:, team:, team_season:, home: true)
      create(:team_game, game:, team: opponent, team_season: opponent_team_season, home: false)
      prediction = create(
        :prediction,
        game:,
        home_team_snapshot: home_snapshot,
        away_team_snapshot: opponent_snapshot,
        ratings_config_version: config,
        home_score: 71.3,
        away_score: 66.1,
        home_win_probability: 0.634,
        pace: 68.0
      )
      final_game = create(
        :game,
        season:,
        start_time: 1.day.ago,
        status: :final,
        home_team_score: 75,
        away_team_score: 68
      )
      create(:team_game, game: final_game, team:, team_season:, home: true)
      create(:team_game, game: final_game, team: opponent, team_season: opponent_team_season, home: false)

      get "/teams/#{team.slug}", params: { year: season.year }
      document = response.parsed_body
      table = document.at_css('.overflow-x-auto > table')
      score_cells = table.css('tbody tr td').map { |cell| cell.text.strip }
      prediction_link = table.css("a[href='/games/#{game.id}']").find do |link|
        link.text.include?(prediction.predicted_score_string)
      end

      expect(response).to have_http_status(:success)
      expect(table.css('th').map { |cell| cell.text.strip }).to eq(['Date', 'Opponent', 'Result', 'Score', 'Prediction', 'Correct?'])
      expect(score_cells).to include(opponent.school, 'Scheduled', '-', 'W', '68 - 75', '—')
      expect(prediction_link).to be_present
      expect(table.at_css("a[href='/teams/#{opponent.slug}']").text).to eq(opponent.school)
      expect(table.at_css("a[href='/games/#{final_game.id}']").text).to include(final_game.start_time.to_date.to_s)
    end

    it 'renders when the team season has no conference membership' do
      season = create(:season, :current, year: 2026, start_date: Date.new(2025, 11, 1), end_date: Date.new(2026, 4, 1))
      config = create(:ratings_config_version, name: 'v1.2-default', current: true)
      team = create(:team, school: 'Independent Team', slug: 'independent-team')
      team_season = create(:team_season, team:, season:, wins: 10, losses: 5, conference_wins: 0, conference_losses: 0)
      create(
        :team_rating_snapshot,
        team_season:,
        team:,
        season:,
        ratings_config_version: config,
        snapshot_date: Date.current,
        rating: 25.0,
        stats: snapshot_stats
      )

      get "/teams/#{team.slug}", params: { year: season.year }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Independent')
      expect(response.parsed_body.css('.overflow-x-auto > table tbody tr')).to be_empty
    end
  end
end
