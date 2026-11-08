# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Daily prediction results' do
  let!(:fixture) { build_daily_forecast }
  let(:game) { fixture[0] }
  let(:odds) { fixture[2] }

  it 'shows saved final results and simulated one-unit summaries on both existing pages' do
    BetRecommendationGenerator.call(game:)
    odds.update!(spread_away_odds: -999, spread_point: 20, moneyline_away: -500, total_points: 200)
    game.update!(status: :final, home_team_score: 70, away_team_score: 80)

    get schedule_games_path(date: game.schedule_date)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Model result', 'Correct', 'Straight-up', '1–0', '100.0%', 'graded: 1', 'pending: 0')
    expect(response.parsed_body.at_css('[aria-label="Schedule"]')).to be_present

    get betting_games_path(date: game.schedule_date, sort: 'spread')
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Final: 80 - 70', 'Win', 'Realized ROI:', 'Expected ROI:',
                                     'simulated at saved consensus odds', 'All bets', '+150', '-110')
    expect(response.parsed_body.at_css('[aria-label="Betting recommendations"]')).to be_present
    expect(response.parsed_body.at_css('tr[data-ev-for-spread]')['data-ev-for-spread']).not_to eq('-999')
    expect(response.parsed_body.at_css('[aria-label="Betting recommendations"]').text).not_to include('-500', '-999')
  end

  context 'without an active model' do
    let!(:fixture) { build_daily_forecast(ratings_config_version: RatingsConfigVersion.publish!) }

    it 'retains the published default forecast, saved picks and settled totals' do
      BetRecommendationGenerator.call(game:)
      expect(RatingsConfigVersion.current).to be_nil
      expect(RatingsConfigVersion.published_default).to eq(fixture[3])
      expect(BetRecommendationIssue.last.prediction_id).to eq(fixture[1].id)
      game.update!(status: :final, home_team_score: 70, away_team_score: 80)

      get betting_games_path(date: game.schedule_date, sort: 'spread')

      expect(response).to have_http_status(:ok)
      table = response.parsed_body.at_css('[aria-label="Betting recommendations"]')
      expect(table.text).to include('Predicted Score:', 'Recommended bet:', '+150', 'Win', 'Realized ROI:')
      expect(table.at_css('tr[data-ev-for-spread]')['data-ev-for-spread']).not_to eq('-999')
      totals = response.parsed_body.at_css('[aria-label="Daily betting performance"] tbody tr:last-child')
      expect(totals.css('td')[1].text).to eq('3')
      expect(totals.css('td')[2].text).to eq('3u')
    end
  end

  it 'keeps empty and no-graded summaries explicit and excludes neighboring Eastern dates' do
    adjacent = create(:game, season: game.season, start_time: Game.schedule_day_range(game.schedule_date + 1).begin,
                             home_team_name: 'Adjacent date')
    get schedule_games_path(date: game.schedule_date)
    expect(response.body).to include('Pending', 'graded: 0', 'Accuracy: N/A')
    expect(response.body).not_to include('Adjacent date')
    get betting_games_path(date: adjacent.schedule_date + 2)
    expect(response.body).to include('No games with odds available', 'All bets', 'N/A')
  end

  it 'hides saved picks and grades for a retained replacement source final' do
    BetRecommendationGenerator.call(game:)
    payload = { 'source_status' => 'final', 'source_completed' => true, 'schedule_date' => game.schedule_date.iso8601,
                'home' => { 'name' => game.home_team_name, 'score' => 81, 'stats' => {} },
                'away' => { 'name' => 'Replacement College', 'score' => 80, 'stats' => {} } }
    source = GameObservation.create!(provider: 'cbbd', external_game_id: 'saved-issue-replacement', outcome: 'conflict',
                                     reason: 'participant_or_orientation_conflict', normalized_payload: payload)
    GameIngestionIssue.capture!(season: game.season, observation: source, category: 'participants', game:)
    get betting_games_path(date: game.schedule_date)
    text = response.parsed_body.at_css('[aria-label="Betting recommendations"]').text
    expect(text).to include('Replacement College', 'No recommendation', 'Source result is ungraded')
    expect(text).not_to include('Expected ROI:', 'Recommended bet:', 'Model spread:')
    expect(response.parsed_body.at_css('tr[data-ev-for-spread]')['data-ev-for-spread']).to eq('-999')
    expect(game.reload).to be_scheduled
  end

  it 'shows missing probability as unavailable without failing Details' do
    BetRecommendationGenerator.call(game:)
    BetRecommendationIssue.delete_all
    game.bet_recommendations.each { |rec| rec.update!(confidence: nil) }
    get betting_games_path(date: game.schedule_date)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Unavailable', 'Legacy recommendation has no saved pregame issue')
  end
end
