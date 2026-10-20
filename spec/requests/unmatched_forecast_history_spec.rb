# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Unmatched game forecast history' do
  let(:season) { create(:season, :current) }
  let(:config) { create(:ratings_config_version, name: 'v1.2-default', current: true) }
  let(:home_team) { create(:team, school: 'Known Home') }
  let(:away_team) { create(:team, school: 'Captured Away') }
  let(:home_team_season) { create(:team_season, team: home_team, season:) }
  let(:away_team_season) { create(:team_season, team: away_team, season:) }
  let(:game) do
    create(:game, season:, status: :final_unmatched, start_time: 2.days.from_now,
                  home_team_name: home_team.school, away_team_name: away_team.school,
                  home_team_score: 70, away_team_score: 60)
  end

  before do
    create(:team_game, game:, team: home_team, team_season: home_team_season, home: true)
    create(:team_game, game:, team: away_team, team_season: away_team_season, home: false)
  end

  it 'shows the latest legacy forecast on schedule, detail, and team pages without evaluating it' do
    create_legacy_forecast(home_score: 70, away_score: 60, snapshot_date: game.schedule_date - 2.days)
    latest = create_legacy_forecast(home_score: 88, away_score: 72, snapshot_date: game.schedule_date - 1.day)
    game.away_team_game.destroy!

    get '/games/schedule', params: { date: game.schedule_date.to_s }
    schedule_cell = response.parsed_body.at_css('tbody tr').css('td')[3]
    expect(schedule_cell.text).to include(latest.predicted_score_string)
    expect(schedule_cell.text).not_to include('Unverified legacy forecast')
    expect(schedule_cell.at_css('a')['title']).to eq('Historical · Unverified legacy forecast')
    expect(schedule_cell.text).not_to include('60 - 70')

    get "/games/#{game.id}"
    expect(response.body).to include('Unverified legacy forecast', 'Away team 72 - Home team 88')
    expect(response.body).not_to include('Captured Away</a>', 'Actual Outcome', '✔', '✖')

    get "/teams/#{home_team.slug}", params: { year: season.year }
    row = response.parsed_body.at_css('.overflow-x-auto > table tbody tr')
    expect(row.css('td')[4].text).to include(latest.predicted_score_string)
    expect(row.css('td')[4].text).not_to include('Unverified legacy forecast')
    expect(row.css('td')[4].at_css('a')['title']).to eq('Historical · Unverified legacy forecast')
    expect(row.css('td')[5].text.strip).to eq('-')
  end

  it 'prefers a selected frozen pregame forecast over newer legacy history' do
    snapshots = [home_team_season, away_team_season].map do |team_season|
      create(:team_rating_snapshot, :with_forecast_inputs, team_season:, ratings_config_version: config,
                                                           snapshot_date: game.schedule_date - 1.day)
    end
    context = ProphetRatings::ForecastContext.capture(game, snapshots, config)
    pregame = create(
      :prediction, game:, ratings_config_version: config,
                   home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last,
                   forecast_kind: 'pregame', calculation_context: context,
                   revision_key: 'frozen-history', generated_at: game.start_time - 1.hour,
                   forecast_start_time: game.start_time, input_cutoff: game.schedule_date - 1,
                   home_score: 76, away_score: 64, home_win_probability: 0.7, pace: 70,
                   home_offensive_efficiency: 110, away_offensive_efficiency: 100,
                   home_defensive_efficiency: 100, away_defensive_efficiency: 110
    )
    create(:prediction, game:, ratings_config_version: config,
                        home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last,
                        home_score: 88, away_score: 72, home_win_probability: 0.7)
    game.away_team_game.destroy!

    expect(game.historical_prediction(ratings_config_version: config)).to eq(pregame)
  end

  private

  def create_legacy_forecast(home_score:, away_score:, snapshot_date:)
    snapshots = [home_team_season, away_team_season].map do |team_season|
      create(:team_rating_snapshot, team_season:, ratings_config_version: config, snapshot_date:)
    end

    create(:prediction, game:, ratings_config_version: config,
                        home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last,
                        home_score:, away_score:, home_win_probability: 0.7)
  end
end
