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
      create(:prediction, game: final_game, home_team_snapshot: home_snapshot, away_team_snapshot: opponent_snapshot,
                          ratings_config_version: config, home_score: 75, away_score: 68,
                          home_win_probability: 0.7, pace: 68.0)
      missing_probability_game = create(:game, season:, start_time: 2.days.ago, status: :final,
                                               home_team_score: 72, away_team_score: 65,
                                               home_team_name: team.school, away_team_name: opponent.school)
      create(:team_game, game: missing_probability_game, team:, team_season:, home: true)
      create(:team_game, game: missing_probability_game, team: opponent, team_season: opponent_team_season, home: false)
      create(:prediction, game: missing_probability_game, home_team_snapshot: home_snapshot,
                          away_team_snapshot: opponent_snapshot, ratings_config_version: config,
                          home_score: 72, away_score: 65, home_win_probability: nil, pace: 68.0)

      get "/teams/#{team.slug}", params: { year: season.year }
      document = response.parsed_body
      table = document.at_css('.overflow-x-auto > table')
      score_cells = table.css('tbody tr td').map { |cell| cell.text.strip }
      prediction_link = table.css("a[href='/games/#{game.id}']").find do |link|
        link.text.include?(prediction.predicted_score_string)
      end

      expect(response).to have_http_status(:success)
      expect(table.css('th').map { |cell| cell.text.strip }).to eq(['Date', 'Opponent', 'Result', 'Score', 'Prediction', 'Correct?'])
      expect(document.text.gsub(/\s+/, ' ')).to include('10-5 (4-2 in TC)')
      conference_link = document.css('a').find { |link| link.text == 'TC' }
      expect(conference_link['href']).to eq(conference_path(conference, season: season.year))
      expect(document.css('a').map(&:text)).not_to include('Conferences')
      expect(score_cells).to include(opponent.school, 'Scheduled', '-', 'W', '68 - 75')
      expect(prediction_link).to be_present
      expect(prediction_link['title']).to eq(prediction.provenance_label)
      table.css('[popover]').remove
      expect(table.text).not_to include(prediction.provenance_label)
      expect(table.at_css("a[href='/teams/#{opponent.slug}']").text).to eq(opponent.school)
      expect(table.at_css("a[href='/games/#{final_game.id}']").text).to include(final_game.start_time.to_date.to_s)
      final_row = table.css('tbody tr').find { |row| row.at_css("a[href='/games/#{final_game.id}']") }
      expect(final_row.css('td')[4].text).to include('68 - 75')
      expect(final_row.css('td')[5].text).to include('✔')
      missing_probability_row = table.css('tbody tr').find do |row|
        row.at_css("a[href='/games/#{missing_probability_game.id}']")
      end
      expect(missing_probability_row.css('td')[5].text.strip).to eq('-')
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
      independent_label = response.parsed_body.css('span').find { |span| span.text.include?('Independent') }
      expect(independent_label.at_css('a')).to be_nil
      expect(response.parsed_body.css('.overflow-x-auto > table tbody tr')).to be_empty
    end

    it 'links to the conference membership for the displayed historical season' do
      historical_season = create(:season, year: 2025, start_date: Date.new(2024, 11, 1), end_date: Date.new(2025, 4, 1))
      current_season = create(:season, :current, year: 2026, start_date: Date.new(2025, 11, 1), end_date: Date.new(2026, 4, 1))
      old_conference = create(:conference, name: 'Old Conference', abbreviation: 'OLD')
      new_conference = create(:conference, name: 'New Conference', abbreviation: 'NEW')
      team = create(:team, school: 'Realigned Team')
      create(:team_conference, team:, conference: old_conference, start_season: historical_season, end_season: historical_season)
      create(:team_conference, team:, conference: new_conference, start_season: current_season)
      create(:team_season, team:, season: historical_season, wins: 18, losses: 1, conference_wins: 10, conference_losses: 0)
      create(:team_season, team:, season: current_season, wins: 1, losses: 18, conference_wins: 0, conference_losses: 10)

      get "/teams/#{team.slug}", params: { year: historical_season.year }

      document = response.parsed_body
      conference_link = document.css('a').find { |link| link.text == 'OLD' }
      expect(response).to have_http_status(:success)
      expect(document.text.gsub(/\s+/, ' ')).to include('18-1 (10-0 in OLD)')
      expect(conference_link['href']).to eq(conference_path(old_conference, season: historical_season.year))
      expect(document.css('a').map(&:text)).not_to include('NEW')
    end

    it 'uses the conference name when its abbreviation is blank or missing' do
      season = create(:season, :current, year: 2026, start_date: Date.new(2025, 11, 1), end_date: Date.new(2026, 4, 1))
      ['', nil].each_with_index do |abbreviation, index|
        conference = create(:conference, name: "Conference Without Abbreviation #{index}", abbreviation:)
        team = create(:team, school: "Unabbreviated Team #{index}")
        create(:team_conference, team:, conference:, start_season: season)
        create(:team_season, team:, season:, wins: 5, losses: 2, conference_wins: 3, conference_losses: 1)

        get "/teams/#{team.slug}", params: { year: season.year }

        label = response.parsed_body.css('span').find { |span| span.text.include?(conference.name) }
        expect(label.at_css('a')['href']).to eq(conference_path(conference, season: season.year))
        expect(label.at_css('a').text).to eq(conference.name)
      end
    end

    it 'shows unmatched home and away results with stored opponent names and no evaluation verdict' do
      season = create(:season, :current, year: 2026, start_date: Date.new(2025, 11, 1), end_date: Date.new(2026, 4, 1))
      create(:ratings_config_version, name: 'v1.2-default', current: true)
      team = create(:team, school: 'Known Team', slug: 'known-team')
      team_season = create(:team_season, team:, season:, wins: 8, losses: 4, conference_wins: 0, conference_losses: 0)
      create(:team_rating_snapshot, team_season:, team:, season:, ratings_config_version: RatingsConfigVersion.current,
                                    snapshot_date: Date.current, rating: nil, overall_rank: nil, stats: {})
      home_win = create(:game, season:, start_time: 1.day.ago, status: :final_unmatched,
                               home_team_name: team.school, away_team_name: 'A Very Long Unmatched Opponent Name',
                               home_team_score: 72, away_team_score: 61)
      create(:team_game, game: home_win, team:, team_season:, home: true)
      away_loss = create(:game, season:, start_time: 2.days.ago, status: :final_unmatched,
                                home_team_name: 'Unresolved Home School', away_team_name: team.school,
                                home_team_score: 80, away_team_score: 70)
      create(:team_game, game: away_loss, team:, team_season:, home: false)
      away_win = create(:game, season:, start_time: 3.days.ago, status: :final_unmatched,
                               home_team_name: 'Unresolved Winning Home', away_team_name: team.school,
                               home_team_score: 60, away_team_score: 65)
      create(:team_game, game: away_win, team:, team_season:, home: false)
      home_loss = create(:game, season:, start_time: 4.days.ago, status: :final_unmatched,
                                home_team_name: team.school, away_team_name: 'Unresolved Winning Away',
                                home_team_score: 70, away_team_score: 75)
      create(:team_game, game: home_loss, team:, team_season:, home: true)

      get "/teams/#{team.slug}", params: { year: season.year }

      document = response.parsed_body
      table = document.at_css('.overflow-x-auto > table')
      rows = table.css('tbody tr')
      expect(response).to have_http_status(:success)
      expect(document.text).to include('8-4')
      expect(rows.size).to eq(4)
      opponent_cells = rows.map { |row| row.css('td')[1].text.gsub(/\s+/, ' ').strip }
      expect(opponent_cells).to include('A Very Long Unmatched Opponent Name', '@ Unresolved Home School',
                                        '@ Unresolved Winning Home', 'Unresolved Winning Away')
      expect(rows.map { |row| row.css('td')[2].text.strip }.sort).to eq(%w[L L W W])
      expect(rows.map { |row| row.css('td')[3].text.strip }).to include('61 - 72', '70 - 80', '65 - 60', '75 - 70')
      expect(rows.map { |row| row.css('td')[5].text.strip }).to all(eq('-'))
      [home_win, away_loss, away_win, home_loss].each do |game|
        expect(table.at_css("a[href='/games/#{game.id}']")).to be_present
      end
      expect(document.css("a[href^='/teams/']").map(&:text)).not_to include('A Very Long Unmatched Opponent Name', 'Unresolved Home School')
      expect(document.text).to include('N/A')
      expect(table.ancestors.any? { |node| node['class']&.include?('overflow-x-auto') }).to be(true)
    end

    it 'retains a captured forecast when the known team has no current rating snapshot' do
      season = create(:season, :current, year: 2026, start_date: Date.new(2025, 11, 1), end_date: Date.new(2026, 4, 1))
      config = create(:ratings_config_version, name: 'v1.2-default', current: true)
      team = create(:team, school: 'Known Home', slug: 'known-home')
      opponent = create(:team, school: 'Captured Away')
      team_season = create(:team_season, team:, season:)
      opponent_season = create(:team_season, team: opponent, season:)
      game = create(:game, season:, start_time: 2.days.from_now, status: :final_unmatched,
                           home_team_name: team.school, away_team_name: opponent.school,
                           home_team_score: 70, away_team_score: 65)
      create(:team_game, game:, team:, team_season:, home: true)
      unresolved_side = create(:team_game, game:, team: opponent, team_season: opponent_season, home: false)
      snapshots = [team_season, opponent_season].map do |entry|
        create(:team_rating_snapshot, :with_forecast_inputs, team_season: entry,
                                                             ratings_config_version: config,
                                                             snapshot_date: game.schedule_date - 1)
      end
      context = ProphetRatings::ForecastContext.capture(game, snapshots, config)
      prediction = create(:prediction, game:, ratings_config_version: config,
                                       home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last,
                                       forecast_kind: 'pregame', calculation_context: context,
                                       revision_key: 'team-history', generated_at: game.start_time - 1.hour,
                                       forecast_start_time: game.start_time, input_cutoff: game.schedule_date - 1,
                                       home_score: 72, away_score: 66, home_win_probability: 0.7, pace: 70,
                                       home_offensive_efficiency: 110, away_offensive_efficiency: 100,
                                       home_defensive_efficiency: 100, away_defensive_efficiency: 110)
      unresolved_side.destroy!
      prediction.update_columns(home_team_snapshot_id: nil, away_team_snapshot_id: nil) # rubocop:disable Rails/SkipsModelValidations
      snapshots.each(&:destroy!)

      get "/teams/#{team.slug}", params: { year: season.year }

      row = response.parsed_body.at_css('.overflow-x-auto > table tbody tr')
      expect(response).to have_http_status(:success)
      expect(row.css('td')[1].text.strip).to eq('Captured Away')
      expect(row.css('td')[4].text).to include('66 - 72')
      expect(row.css('td')[4].at_css('[popover]').text).to include('Historical pregame forecast')
      row.css('[popover]').remove
      expect(row.css('td')[4].text).not_to include('Historical pregame forecast')
      expect(row.css('td')[4].at_css('a')['title']).to eq('Historical pregame forecast')
      expect(row.css('td')[5].text.strip).to eq('-')
    end
  end
end
