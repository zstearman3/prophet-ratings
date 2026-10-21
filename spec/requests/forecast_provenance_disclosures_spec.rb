# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Forecast provenance disclosures' do
  let(:season) { create(:season, :current) }
  let(:config) { create(:ratings_config_version, name: 'v1.2-default', current: true) }
  let(:participants) { create_list(:team_season, 2, season:) }
  let(:game) do
    create(:game, season:, status: :scheduled, start_time: 2.days.from_now,
                  home_team_name: participants.first.team.school, away_team_name: participants.last.team.school)
  end
  let(:snapshots) do
    participants.map do |team_season|
      create(:team_rating_snapshot, :with_forecast_inputs, team_season:, ratings_config_version: config,
                                                           snapshot_date: game.schedule_date - 1)
    end
  end

  before do
    participants.each_with_index do |participant, index|
      create(:team_game, game:, team: participant.team, team_season: participant, home: index.zero?)
    end
  end

  def create_forecast(kind, home_score: 76, revision_key: kind, generated_at: game.start_time - 1.hour)
    attributes = { game:, ratings_config_version: config, home_team_snapshot: snapshots.first,
                   away_team_snapshot: snapshots.last, home_score:, away_score: 64, home_win_probability: 0.7, pace: 70 }
    unless kind == 'legacy_unverified'
      attributes.merge!(forecast_kind: kind, calculation_context: ProphetRatings::ForecastContext.capture(game, snapshots, config),
                        revision_key:, generated_at:, forecast_start_time: game.start_time,
                        input_cutoff: game.schedule_date - 1, home_offensive_efficiency: 110, away_offensive_efficiency: 100,
                        home_defensive_efficiency: 100, away_defensive_efficiency: 110)
    end
    create(:prediction, **attributes)
  end

  def request_table(page)
    if page == 'team'
      get "/teams/#{participants.first.team.slug}", params: { year: season.year }
      response.parsed_body.at_css('.overflow-x-auto > table')
    else
      get "/games/#{page}", params: { date: game.schedule_date.to_s }
      response.parsed_body.at_css('table')
    end
  end

  def expect_disclosure(table, label)
    disclosure = table.at_css('.forecast-provenance')
    expect(disclosure).to be_present
    popover = disclosure.at_css('[popover="auto"]')
    expect(popover).to be_present
    expect(popover['role']).to eq('tooltip')
    expect_provenance_trigger(disclosure.at_css('button'), popover['id'])
    expect(popover.text.strip).to eq(label)
    expect_compact_table(table, label)
  end

  def expect_provenance_trigger(trigger, popover_id)
    expect(trigger).to be_present
    expect(trigger['type']).to eq('button')
    expect(trigger['aria-label']).to eq('Forecast provenance')
    expect(trigger['class']).to include('focus-visible:ring-2')
    expect(trigger['popovertarget']).to eq(popover_id)
    expect(trigger['aria-describedby']).to eq(popover_id)
  end

  def expect_compact_table(table, label)
    compact_table = table.dup
    compact_table.css('[popover]').remove
    expect(compact_table.text).not_to include(label)
  end

  kinds = { 'pregame' => 'Saved pregame forecast', 'legacy_unverified' => 'Unverified legacy forecast' }.freeze
  %w[schedule team betting].each do |page|
    kinds.each do |kind, label|
      it "exposes #{kind} provenance beside the #{page} score with a compact native disclosure" do
        prediction = create_forecast(kind)

        table = request_table(page)

        expect(response).to have_http_status(:success)
        score = table.at_css("[title='#{label}']")
        expect(score.text).to include(page == 'betting' ? prediction.predicted_score_with_teams : '64 - 76')
        expect_disclosure(table, label)
      end
    end

    it "keeps missing #{page} scores safe while disclosing their provenance" do
      create_forecast('legacy_unverified', home_score: nil)

      table = request_table(page)

      expect(response).to have_http_status(:success)
      expect(table.text).to include('Prediction unavailable')
      expect_disclosure(table, 'Unverified legacy forecast')
    end

    it "does not substitute a reconstruction in the #{page} table" do
      create_forecast('reconstruction')

      table = request_table(page)

      expect(response).to have_http_status(:success)
      expect(game.reload.current_prediction).to be_nil
      expect(table.at_css('.forecast-provenance')).to be_nil
      expect(table.text).not_to include('64 - 76', 'Postgame reconstruction')
    end
  end

  kinds.each do |kind, label|
    it "keeps #{kind} provenance behind the game detail info control" do
      create_forecast(kind)

      get "/games/#{game.id}"

      expect(response).to have_http_status(:success)
      expect_disclosure(response.parsed_body, label)
    end
  end

  it 'keeps historical game detail provenance behind the same info control' do
    create_forecast('pregame')
    game.update!(status: :final_unmatched, home_team_score: 70, away_team_score: 60)
    game.away_team_game.destroy!

    get "/games/#{game.id}"

    expect(response).to have_http_status(:success)
    expect_disclosure(response.parsed_body, 'Historical pregame forecast')
    expect(response.parsed_body.text).to include('no evaluation result')
  end

  it 'selects the betting forecast only once for its condition, title, disclosure and score' do
    create_forecast('pregame')
    selections = []
    subscriber = lambda do |*args|
      sql = args.last[:sql]
      selections << sql if sql.include?('SELECT "predictions".*') && sql.include?('DISTINCT ON')
    end

    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') { request_table('betting') }

    expect(selections.size).to eq(1)
  end

  it 'offers a named keyboard and touch toggle for the hidden betting details' do
    create_forecast('pregame')

    table = request_table('betting')

    toggle = table.at_css('button[data-betting-expand-target="toggle"]')
    expect(toggle).to be_present
    expect(toggle['type']).to eq('button')
    expect(toggle['aria-label']).to include('Betting details', game.home_team_name, game.away_team_name)
    expect(toggle['aria-expanded']).to eq('false')
    expect(toggle['class']).to include('focus-visible:ring-2')
    expect(table.at_css("##{toggle['aria-controls']}")['class']).to include('hidden')
  end

  %w[pregame legacy_unverified].each do |kind|
    it "marks a #{kind} betting forecast historical after matching participants are restored to an unmatched result" do
      prediction = create_forecast(kind)
      create_forecast(kind, home_score: 88, revision_key: 'older', generated_at: game.start_time - 2.hours) if kind == 'pregame'
      create(:team_alias, team: participants.first.team, value: game.home_team_name, source: 'sports_reference')
      Importer::GamesImporter.import_game(
        { date: game.start_time, url: game.url, home_team: game.home_team_name, away_team: 'Unresolved Opponent',
          home_team_score: 70, away_team_score: 60, source_completed: true }, season:
      )
      expect(game.reload).to be_final_unmatched
      expect(game.away_team_game).to be_nil
      expect(game.current_prediction).to be_nil
      expect(game.historical_prediction).to eq(prediction)
      excluded_table = request_table('betting')
      expect(excluded_table.text).to include('Missing current participants')
      expect(excluded_table.text).not_to include('Predicted Score:')
      expect(excluded_table.at_css('.forecast-provenance')).to be_nil

      # A persisted participant repair can restore the captured identity before the result is finalized.
      create(:team_game, game:, team: participants.last.team, team_season: participants.last, home: false)
      expect(game.reload.current_prediction).to eq(prediction)
      expect(prediction.reload.participant_exclusion_reason).to be_nil

      table = request_table('betting')
      label = kind == 'pregame' ? 'Historical pregame forecast' : 'Historical · Unverified legacy forecast'
      score = table.at_css("[title='#{label}']")
      expect(score).to be_present
      expect(score.text).to include(prediction.predicted_score_with_teams)
      expect_disclosure(table, label)
    end
  end
end
