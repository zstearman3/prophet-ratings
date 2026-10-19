# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Forecast participant safety' do
  let(:season) { create(:season, :current) }
  let(:version) { create(:ratings_config_version, current: true) }
  let(:teams) { create_list(:team_season, 2, season:) }
  let(:game) do
    create(:game, season:, start_time: 2.days.from_now, status: :final,
                  home_team_score: 77, away_team_score: 70, possessions: 70, minutes: 40)
  end
  let(:snapshots) do
    teams.map do |team|
      create(:team_rating_snapshot, :with_forecast_inputs, team_season: team,
                                                           ratings_config_version: version, snapshot_date: game.schedule_date - 1)
    end
  end
  let(:prediction) { forecast('pregame') }

  before do
    recreate_sides(teams)
    prediction
  end

  def forecast(kind)
    context = if kind == 'pregame'
                ProphetRatings::ForecastContext.capture(game, snapshots, version)
              else
                prediction.calculation_context
              end
    create(:prediction, game:, ratings_config_version: version,
                        home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last,
                        forecast_kind: kind, calculation_context: context, revision_key: kind,
                        generated_at: game.start_time - 1.hour, forecast_start_time: game.start_time,
                        input_cutoff: game.schedule_date - 1, home_score: 77, away_score: 70,
                        home_win_probability: 0.75, pace: 70,
                        home_offensive_efficiency: 110, away_offensive_efficiency: 100,
                        home_defensive_efficiency: 100, away_defensive_efficiency: 110)
  end

  def recreate_sides(participants)
    TeamGame.where(game:).destroy_all
    participants.each_with_index do |team, index|
      create(:team_game, game:, team: team.team, team_season: team, home: index.zero?,
                         offensive_efficiency: index.zero? ? 110 : 100,
                         defensive_efficiency: index.zero? ? 100 : 110)
    end
    game.reload
  end

  def evaluator(mode = 'pregame')
    ProphetRatings::PredictionEvaluator.new(ratings_config_version: version,
                                            date_range: game.schedule_date..game.schedule_date, mode:)
  end

  shared_examples 'an excluded correction' do |reason|
    it 'excludes all outcome consumers and preserves the issuance and replay' do
      prediction.reload
      original = prediction.attributes
      replay = prediction.replay
      expect(game.current_prediction(ratings_config_version: version)).to be_nil
      expect(game.current_prediction_unavailable_reason(ratings_config_version: version)).to eq(reason)
      expect(ProphetRatings::EvaluationObservation.new(prediction).call).to be_nil
      expect(evaluator.call[:coverage]).to include(selected: 1, evaluated: 0, excluded_invalid: 1,
                                                   excluded_by_reason: { reason => 1 })
      expect(evaluator.observations).to be_empty
      expect(evaluator.call[:games]).to eq(0)
      expect(ProphetRatings::GameFinalizer.prediction_error_attributes(prediction)).to be_nil
      ProphetRatings::GameFinalizer.new(game).send(:finalize_prediction!)
      expect(prediction.reload.attributes).to eq(original)
      expect(prediction.replay).to eq(replay)
    end

    [false, true].each do |verified_only|
      it "excludes stored residuals from learning (verified_only=#{verified_only})" do
        prediction.update!(home_offensive_efficiency_error: 999, home_defensive_efficiency_error: 999, pace_error: 999)
        aggregator = ProphetRatings::TeamSeasonStatsAggregator.new(season:, as_of: game.schedule_date,
                                                                   ratings_config_version: version, verified_only:)
        aggregator.run
        expect(aggregator.excluded_prediction_counts).to eq(reason => 1)
        expect(teams.first.reload).to have_attributes(offensive_efficiency_volatility: 11.5, defensive_efficiency_volatility: 11.5,
                                                      pace_volatility: 4.5, home_offense_boost: 2.2, home_defense_boost: -2.2)
        expect(prediction.reload.home_offensive_efficiency_error).to eq(999)
      end
    end
  end

  context 'when persisted side reversal' do
    before do
      recreate_sides(teams.reverse)
      game.update!(home_team_score: 70, away_team_score: 77)
    end

    it_behaves_like 'an excluded correction', 'participant_side_mismatch'

    it 'does not fall back to an aligned legacy forecast' do
      create(:prediction, game:, ratings_config_version: version, home_team_snapshot: snapshots.last, away_team_snapshot: snapshots.first)
      expect(game.current_prediction(ratings_config_version: version)).to be_nil
      expect(Prediction.selected_with_legacy.where(game:).pluck(:id)).to eq([prediction.id])
    end

    %w[legacy_unverified reconstruction].each do |kind|
      it "rejects #{kind} exploratory outcome attribution" do
        forecast(kind)
        expect(evaluator(kind).call[:coverage]).to include(evaluated: 0, excluded_by_reason: { 'participant_side_mismatch' => 1 })
      end
    end
  end

  context 'when participant replacement' do
    before { recreate_sides([teams.first, create(:team_season, season:)]) }

    it_behaves_like 'an excluded correction', 'participant_side_mismatch'
  end

  context 'when a side is removed' do
    before { recreate_sides([teams.first]) }

    it_behaves_like 'an excluded correction', 'missing_current_participants'

    it 'renders the final game with its exclusion reason' do
      get "/games/#{game.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Missing current participants')
      expect(response.body).not_to include('Predicted Score:')
    end
  end

  it 'uses captured identities even after the source snapshot identity changes' do
    replacement = create(:team_season, season:)
    snapshots.first.update!(team: replacement.team, team_season: replacement)
    expect(prediction.reload.participant_exclusion_reason).to be_nil
    recreate_sides([replacement, teams.last])
    expect(prediction.reload.participant_exclusion_reason).to eq('participant_side_mismatch')
  end

  it 'rejects missing captured identities without consulting mutable snapshots' do
    context = prediction.calculation_context.deep_dup
    context['snapshots'][0]['source']['team_season_id'] = nil
    prediction.update_column(:calculation_context, context) # rubocop:disable Rails/SkipsModelValidations
    expect(prediction.reload.participant_exclusion_reason).to eq('missing_captured_participants')
  end

  it 'requires both the captured team and team-season identity on each side' do
    other_season = create(:season, year: season.year + 1)
    other_team_season = create(:team_season, team: teams.first.team, season: other_season)
    game.home_team_game.update!(team_season: other_team_season)
    expect(prediction.reload.participant_exclusion_reason).to eq('participant_side_mismatch')
  end

  it 'accepts recreated matching sides and recomputes score-only corrections without changing issuance' do
    original = prediction.attributes
    expect(game.current_prediction(ratings_config_version: version)).to eq(prediction)
    expect(ProphetRatings::EvaluationObservation.new(prediction).call[:margin_error]).to eq(0)
    game.update!(home_team_score: 78)
    expect(ProphetRatings::EvaluationObservation.new(prediction).call[:margin_error]).to eq(-1)
    expect(ProphetRatings::GameFinalizer.prediction_error_attributes(prediction)).to include(pace_error: 0)
    expect(prediction.reload.attributes).to eq(original)
  end

  it 'uses snapshot identities for empty-context legacy and rejects absent legacy identities' do
    legacy = create(:prediction, game:, ratings_config_version: version, home_team_snapshot: snapshots.first,
                                 away_team_snapshot: snapshots.last)
    expect(legacy.participant_exclusion_reason).to be_nil
    recreate_sides(teams.reverse)
    expect(legacy.reload.participant_exclusion_reason).to eq('participant_side_mismatch')
    legacy.update_column(:home_team_snapshot_id, nil) # rubocop:disable Rails/SkipsModelValidations
    expect(legacy.reload.participant_exclusion_reason).to eq('missing_captured_participants')
  end

  it 'hides persisted betting recommendations and saved model values after participant correction' do
    odd = create(:game_odd, game:, fetched_at: Time.current, spread_point: -3.5, total_points: 147)
    recommendation = create(:bet_recommendation, :total, game:, game_odd: odd, prediction:, ratings_config_version: version, current: true,
                                                         model_value: 987.654)
    create(:bet_recommendation, game:, game_odd: odd, prediction:, ratings_config_version: version, current: true)
    original = recommendation.attributes
    get '/games/betting', params: { date: game.schedule_date.to_s }
    expect(response.body).to include('987.654', 'Model Value:')
    recreate_sides(teams.reverse)
    get '/games/betting', params: { date: game.schedule_date.to_s }
    expect(response).to have_http_status(:success)
    expect(response.body).to include('Participant side mismatch')
    expect(response.body).not_to include('987.654', 'Predicted Total:', 'Model Value:')
    expect(recommendation.reload.attributes).to eq(original)
  end
end
