# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Games' do
  describe 'GET /schedule' do
    it 'returns http success' do
      season = create(:season, :current)
      team = create(:team)
      team_season = create(:team_season, team:, season:)
      game = create(:game, start_time: Date.current.beginning_of_day + 12.hours, status: :final, minutes: 40, home_team_score: 70,
                           away_team_score: 65, venue_name: 'Arena', season:)
      create(:team_game, game:, team:, team_season:)
      get '/games/schedule', params: { date: Date.current.to_s }
      expect(response).to have_http_status(:success)
    end

    it 'renders scheduled games with a dash score and a linked prediction' do
      season = create(:season, :current)
      config = create(:ratings_config_version, name: 'v1.2-default', current: true)
      home_team = create(:team, school: 'Home Team', slug: 'home-team')
      away_team = create(:team, school: 'Away Team', slug: 'away-team')
      home_team_season = create(:team_season, team: home_team, season:)
      away_team_season = create(:team_season, team: away_team, season:)
      game = create(
        :game,
        season:,
        start_time: Date.current.beginning_of_day + 12.hours,
        status: :scheduled,
        home_team_name: home_team.school,
        away_team_name: away_team.school
      )
      create(:team_game, game:, team: home_team, team_season: home_team_season, home: true)
      create(:team_game, game:, team: away_team, team_season: away_team_season, home: false)
      home_snapshot = create(
        :team_rating_snapshot,
        team_season: home_team_season,
        team: home_team,
        season:,
        ratings_config_version: config,
        snapshot_date: Date.current
      )
      away_snapshot = create(
        :team_rating_snapshot,
        team_season: away_team_season,
        team: away_team,
        season:,
        ratings_config_version: config,
        snapshot_date: Date.current
      )
      prediction = create(
        :prediction,
        game:,
        home_team_snapshot: home_snapshot,
        away_team_snapshot: away_snapshot,
        ratings_config_version: config,
        home_score: 70.2,
        away_score: 65.8,
        home_win_probability: 0.6123,
        pace: 68.0
      )

      get '/games/schedule', params: { date: Date.current.to_s }
      document = response.parsed_body
      score_cell = document.css('table tbody tr td')[2]
      prediction_link = document.css("a[href='/games/#{game.id}']").find do |link|
        link.text.include?(prediction.predicted_score_string)
      end

      expect(response).to have_http_status(:success)
      expect(score_cell.text.strip).to eq('-')
      expect(prediction_link).to be_present
    end

    it 'uses Eastern schedule dates when selecting games' do
      season = create(:season, :current)
      eastern_time = ActiveSupport::TimeZone['Eastern Time (US & Canada)']
      game = create(
        :game,
        season:,
        start_time: eastern_time.parse('2026-03-11 11:30pm'),
        status: :scheduled,
        home_team_name: 'Late Home',
        away_team_name: 'Late Away'
      )

      get '/games/schedule', params: { date: '2026-03-11' }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(game.home_team_name)
      expect(response.body).to include(game.away_team_name)
    end

    it 'renders stored scores and a public Final label for unmatched results' do
      season = create(:season, :current)
      game = create(:game, season:, start_time: Date.current.beginning_of_day + 12.hours,
                           status: :final_unmatched, away_team_score: 65, home_team_score: 70)

      get '/games/schedule', params: { date: Date.current.to_s }

      row = response.parsed_body.at_css('tbody tr')
      expect(row.css('td')[1].text).to include('Final')
      expect(row.css('td')[1].text).not_to include('FINAL_UNMATCHED')
      expect(row.css('td')[2].text.strip).to eq('65 - 70')
      expect(row.at_css("a[href='/games/#{game.id}']")).to be_present
    end
  end

  describe 'GET /games/:id' do
    let(:season) { create(:season, :current) }
    let(:home_team) { create(:team, school: 'Home Team', slug: 'home-team') }
    let(:away_team) { create(:team, school: 'Away Team', slug: 'away-team') }
    let(:home_team_season) { create(:team_season, team: home_team, season:) }
    let(:away_team_season) { create(:team_season, team: away_team, season:) }
    let(:venue_name) { nil }
    let(:game) do
      create(
        :game,
        season:,
        start_time: Date.current.beginning_of_day + 12.hours,
        status: :final,
        minutes: 40,
        home_team_score: 70,
        away_team_score: 65,
        home_team_name: home_team.school,
        away_team_name: away_team.school,
        venue_name:
      )
    end

    before do
      create(:team_game, game:, team: home_team, team_season: home_team_season, home: true, points: 70)
      create(:team_game, game:, team: away_team, team_season: away_team_season, home: false, points: 65)
    end

    context 'when venue name is blank' do
      let(:venue_name) { '' }

      it 'does not render the venue header' do
        get "/games/#{game.id}"

        expect(response).to have_http_status(:success)
        expect(response.body).not_to include('Venue:')
      end
    end

    context 'when venue name is present' do
      let(:venue_name) { 'Test Arena' }

      it 'renders the venue header and value' do
        get "/games/#{game.id}"

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Venue: Test Arena')
      end
    end

    context 'when the game is scheduled' do
      let(:game) do
        create(
          :game,
          season:,
          start_time: Date.current.beginning_of_day + 12.hours,
          status: :scheduled,
          home_team_name: home_team.school,
          away_team_name: away_team.school,
          venue_name:
        )
      end

      before do
        TeamGame.delete_all
      end

      it 'renders without assuming final stats are available' do
        get "/games/#{game.id}"

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Box score is available after the game is final.')
        expect(response.body).to include('No prediction available for this game.')
        expect(response.body).not_to include('Actual Outcome')
      end
    end

    it 'renders a saved prediction with partial model output as unavailable' do
      config = create(:ratings_config_version, name: 'v1.2-default', current: true)
      home_snapshot = create(:team_rating_snapshot, team_season: home_team_season, team: home_team,
                                                    season:, ratings_config_version: config, snapshot_date: Date.current)
      away_snapshot = create(:team_rating_snapshot, team_season: away_team_season, team: away_team,
                                                    season:, ratings_config_version: config, snapshot_date: Date.current)
      create(:prediction, game:, ratings_config_version: config,
                          home_team_snapshot: home_snapshot, away_team_snapshot: away_snapshot,
                          home_score: nil, away_score: 65, home_win_probability: 0.6, pace: nil)

      get "/games/#{game.id}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Predicted Score:', 'Win Probability:', 'N/A')
      expect(response.body).not_to include('No prediction available for this game.')
    end

    context 'when the game is an unmatched final' do
      let(:game) do
        create(:game, season:, start_time: Date.current.beginning_of_day + 12.hours,
                      status: :final_unmatched, minutes: nil, home_team_score: 70, away_team_score: 65,
                      home_team_name: 'Known Home', away_team_name: 'Unknown Away')
      end

      before { TeamGame.delete_all }

      it 'renders the final score and unavailable box statistics without inventing a winner link' do
        known_team = create(:team, school: 'Known Home', slug: 'known-home')
        known_team_season = create(:team_season, team: known_team, season:)
        create(:team_game, game:, team: known_team, team_season: known_team_season, home: true,
                           field_goals_made: 0, field_goals_attempted: nil)

        get "/games/#{game.id}"

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Known Home', 'Unknown Away', '70', '65', 'Final')
        expect(response.body).to include('N/A')
        expect(response.parsed_body.css('tbody tr').first.css('td')[1].text.strip).to eq('N/A')
        expect(response.body).not_to include('FINAL_UNMATCHED')
        expect(response.body).not_to include('Winning Team:')
      end

      it 'shows a persisted forecast as historical using captured school names without an evaluation verdict' do
        config = create(:ratings_config_version, name: 'v1.2-default', current: true)
        home_team = create(:team, school: 'Captured Home School')
        away_team = create(:team, school: 'Captured Away School')
        home_season = create(:team_season, team: home_team, season:)
        away_season = create(:team_season, team: away_team, season:)
        home_snapshot = create(:team_rating_snapshot, :with_forecast_inputs, team_season: home_season,
                                                                             ratings_config_version: config,
                                                                             snapshot_date: game.schedule_date - 1)
        away_snapshot = create(:team_rating_snapshot, :with_forecast_inputs, team_season: away_season,
                                                                             ratings_config_version: config,
                                                                             snapshot_date: game.schedule_date - 1)
        game.update!(start_time: 2.days.from_now)
        create(:team_game, game:, team: home_team, team_season: home_season, home: true)
        unresolved_side = create(:team_game, game:, team: away_team, team_season: away_season, home: false)
        captured = ProphetRatings::ForecastContext.capture(game, [home_snapshot, away_snapshot], config)
        create(:prediction, game:, ratings_config_version: config,
                            home_team_snapshot: home_snapshot, away_team_snapshot: away_snapshot,
                            forecast_kind: 'pregame', calculation_context: captured,
                            revision_key: 'historical', generated_at: game.start_time - 1.hour,
                            forecast_start_time: game.start_time, input_cutoff: game.schedule_date - 1,
                            home_score: 74, away_score: 68, home_win_probability: 0.7, pace: 70,
                            home_offensive_efficiency: 110, away_offensive_efficiency: 100,
                            home_defensive_efficiency: 100, away_defensive_efficiency: 110)
        unresolved_side.destroy!

        get "/games/#{game.id}"

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Historical pregame forecast', 'Captured Away School', 'Captured Home School',
                                         'Captured home win probability', 'no evaluation result')
        expect(response.body).not_to include('Actual Outcome', 'Correct?')
      end
    end
  end
end
