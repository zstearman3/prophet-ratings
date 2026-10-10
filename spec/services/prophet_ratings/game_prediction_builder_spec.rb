# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::GamePredictionBuilder do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 10, 10, 16)) { example.run } }

  let(:season) { create(:season, average_efficiency: 100, average_pace: 70) }
  let(:version) { create(:ratings_config_version) }
  let(:game) { create(:game, season:, venue_type: 'neutral', status: :scheduled, start_time: 1.day.from_now) }
  let(:snapshots) do
    [true, false].map do |home|
      team = create(:team_season, season:)
      create(:team_game, game:, team: team.team, team_season: team, home:)
      create(:team_rating_snapshot, team_season: team, ratings_config_version: version,
                                    snapshot_date: game.schedule_date - 1, adj_pace: 70,
                                    offensive_efficiency_volatility: 0, defensive_efficiency_volatility: 0, pace_volatility: 0)
    end
  end

  def build_forecast
    described_class.new(game, ratings_config_version: version).call
  end

  it 'uses the Eastern game date and never reads result statistics' do
    game.update!(start_time: Time.utc(2026, 10, 12, 1)) # October 11 Eastern, October 12 UTC
    snapshots.each do |snapshot|
      snapshot.update!(snapshot_date: Date.new(2026, 10, 10))
      create(:team_rating_snapshot, team_season: snapshot.team_season, ratings_config_version: version,
                                    snapshot_date: Date.new(2026, 10, 11), adj_offensive_efficiency: 200)
    end
    allow(game).to receive(:pace).and_raise('target result access')
    allow(game.home_team_game).to receive(:offensive_efficiency).and_raise('target result access')
    expect(build_forecast.input_cutoff).to eq(Date.new(2026, 10, 10))
    expect(build_forecast.home_team_snapshot).to eq(snapshots.first)
  end

  it 'skips when only game-day inputs exist and leaves a useful log message' do
    snapshots.each { |snapshot| snapshot.update!(snapshot_date: game.schedule_date) }
    allow(Rails.logger).to receive(:warn)
    expect(build_forecast).to be_nil
    expect(Rails.logger).to have_received(:warn).with(/publish complete snapshots before the Eastern game date/)
  end

  it 'replays and diagnoses the same unrounded inputs after sources, venue and season change' do
    snapshots.first.update!(adj_offensive_efficiency: 100.123, offensive_efficiency_volatility: 10)
    prediction = build_forecast
    original = [prediction.replay, prediction.margin_std_deviation, prediction.total_std_deviation]
    snapshots.each do |snapshot|
      snapshot.update!(adj_offensive_efficiency: 150, adj_pace: 90, offensive_efficiency_volatility: 40, pace_volatility: 20)
      snapshot.team_season.update!(offensive_efficiency_volatility: 50)
    end
    season.update!(average_efficiency: 130, average_pace: 80, efficiency_std_deviation: 50)
    game.update!(venue_type: 'home', venue_confidence: 'confirmed')
    prediction.reload
    expect([prediction.replay, prediction.margin_std_deviation, prediction.total_std_deviation]).to eq(original)
    expect(prediction.calculation_context.dig('snapshots', 0, 'ratings', 'adj_offensive_efficiency')).to eq(100.123)
    expect(prediction.home_score.to_f).to eq(original.first[:home_expected_score])
  end

  it 'reuses identical job retries and appends revisions when the same source row is corrected' do
    snapshots
    first = build_forecast
    expect(build_forecast.id).to eq(first.id)
    snapshots.first.update!(adj_offensive_efficiency: 110)
    revised = build_forecast
    expect(revised.id).not_to eq(first.id)
    expect(revised.revision_key).not_to eq(first.revision_key)
    expect(first.reload.home_score).not_to eq(revised.home_score)
    expect(game.current_prediction(ratings_config_version: version)).to eq(revised)
  end

  it 'prevents updates to forecast inputs and outputs but permits attaching outcomes' do
    snapshots
    prediction = build_forecast
    expect { prediction.update!(home_score: 99) }.to raise_error(ActiveRecord::RecordInvalid, /append a revision/)
    prediction.reload.update!(pace_error: 3)
    expect(prediction.reload.pace_error).to eq(3)
    expect { prediction.update!(calculation_context: {}) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'reuses a consecutive retry after timestamp-only source touches without replacing captured provenance' do
    snapshots
    prediction = build_forecast
    original = prediction.calculation_context
    travel 1.minute
    snapshots.each { |snapshot| snapshot.update!(updated_at: Time.current) }
    season.update!(updated_at: Time.current)
    expect(build_forecast.id).to eq(prediction.id)
    expect(prediction.reload.calculation_context).to eq(original)
  end

  it 'appends and selects a fresh issuance when venue inputs revert, then reuses consecutive retries' do
    snapshots
    neutral = build_forecast
    original_venue = game.attributes.slice('venue_type', 'venue_confidence', 'venue_source', 'venue_name', 'neutral')
    game.update!(venue_type: 'home', venue_confidence: 'confirmed', neutral: false)
    home = build_forecast
    game.update!(original_venue)
    restored = build_forecast
    expect([neutral, home, restored].map(&:revision_key).uniq.size).to eq(3)
    expect(restored.replay).to eq(neutral.replay)
    expect(build_forecast.id).to eq(restored.id)
    expect([game.current_prediction(ratings_config_version: version), Prediction.selected_pregame.to_a]).to eq([restored, [restored]])
    game.update!(home_team_score: 80, away_team_score: 70)
    allow(game.home_team_game).to receive_messages(offensive_efficiency: 100, defensive_efficiency: 100)
    allow(game.away_team_game).to receive_messages(offensive_efficiency: 100, defensive_efficiency: 100)
    allow(game).to receive(:pace).and_return(70)
    ProphetRatings::GameFinalizer.new(game, ratings_config_version: version).send(:finalize_prediction!)
    expect([neutral, home, restored].map { |prediction| prediction.reload.pace_error }).to eq([nil, nil, 0])
  end

  it 'attaches legacy outcomes when a reconstruction shares its snapshot pair and still rejects duplicate legacy rows' do
    snapshots
    legacy = create(:prediction, game:, ratings_config_version: version,
                                 home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last,
                                 home_offensive_efficiency: 105, away_offensive_efficiency: 105,
                                 home_defensive_efficiency: 105, away_defensive_efficiency: 105, pace: 70)
    game.update!(status: :final, home_team_score: 80, away_team_score: 70)
    reconstruction = build_forecast
    expect([reconstruction.home_team_snapshot, reconstruction.away_team_snapshot]).to eq(snapshots)
    allow(game.home_team_game).to receive_messages(offensive_efficiency: 100, defensive_efficiency: 100)
    allow(game.away_team_game).to receive_messages(offensive_efficiency: 100, defensive_efficiency: 100)
    allow(game).to receive(:pace).and_return(70)
    ProphetRatings::GameFinalizer.new(game, ratings_config_version: version).send(:finalize_prediction!)
    expect(legacy.reload.home_offensive_efficiency_error).not_to be_nil
    expect(reconstruction.reload.home_offensive_efficiency_error).to be_nil
    expect(Prediction.selected_with_legacy).to contain_exactly(legacy)
    expect(legacy.dup.tap(&:valid?).errors[:game]).to include('has already been taken')
  end

  it 'labels late-created backdated sources as reconstruction after tipoff' do
    snapshots
    game.update!(start_time: 1.hour.ago, status: :final)
    snapshots.each { |snapshot| snapshot.update!(snapshot_date: game.schedule_date - 1) }
    prediction = build_forecast
    expect(prediction.forecast_kind).to eq('reconstruction')
    expect(prediction.generated_at).to be >= snapshots.first.created_at
    expect(game.current_prediction(ratings_config_version: version)).to be_nil
    expect(Prediction.selected_pregame).not_to include(prediction)
    expect(prediction.provenance_label).to eq('Postgame reconstruction')
  end

  it 'rejects backdated sources whose creation or correction timestamp is in the future' do
    snapshots.first.update!(created_at: 1.hour.from_now)
    expect(build_forecast).to be_nil
    snapshots.first.update!(created_at: 1.hour.ago, updated_at: 1.hour.from_now)
    expect(build_forecast).to be_nil
  end

  it 'keeps legacy rows available as explicitly unverified without fabricating generation time' do
    snapshots
    prediction = create(:prediction, game:, ratings_config_version: version,
                                     home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last)
    expect(prediction.provenance_label).to eq('Unverified legacy forecast')
    expect(prediction.generated_at).to be_nil
    expect { prediction.replay }.to raise_error(ArgumentError, /no replayable context/)
    expect(game.current_prediction(ratings_config_version: version)).to eq(prediction)
    expect(Prediction.selected_pregame).to be_empty
  end

  it 'attaches outcomes only to the latest eligible revision without changing its context' do
    snapshots
    first = build_forecast
    snapshots.first.update!(adj_offensive_efficiency: 110)
    selected = build_forecast
    original_context = selected.calculation_context
    game.update!(home_team_score: 80, away_team_score: 70)
    allow(game.home_team_game).to receive_messages(offensive_efficiency: 100, defensive_efficiency: 100)
    allow(game.away_team_game).to receive_messages(offensive_efficiency: 100, defensive_efficiency: 100)
    allow(game).to receive(:pace).and_return(70)
    described_finalizer = ProphetRatings::GameFinalizer.new(game, ratings_config_version: version)
    described_finalizer.send(:finalize_prediction!)
    expect(first.reload.home_offensive_efficiency_error).to be_nil
    expect(selected.reload.home_offensive_efficiency_error).not_to be_nil
    expect(selected.calculation_context).to eq(original_context)
  end

  it 'evaluates one saved pregame issuance and excludes later reconstruction and legacy rows' do
    snapshots
    first = build_forecast
    snapshots.first.update!(adj_offensive_efficiency: 110)
    selected = build_forecast
    game.update!(status: :final, home_team_score: 80, away_team_score: 70)
    reconstruction = build_forecast
    legacy = create(:prediction, game:, ratings_config_version: version,
                                 home_team_snapshot: snapshots.last, away_team_snapshot: snapshots.first)
    evaluator = ProphetRatings::PredictionEvaluator.new(ratings_config_version: version,
                                                        date_range: Time.current..2.days.from_now)
    expect(evaluator.send(:predictions).pluck(:id)).to eq([selected.id])
    expect(evaluator.call[:prediction_accuracy][:total_predictions]).to eq(1)
    expect(game.current_prediction(ratings_config_version: version)).to eq(selected)
    expect(evaluator.send(:predictions)).not_to include(first, reconstruction, legacy)
  end

  it 'does not select a forecast issued after a corrected earlier tipoff' do
    snapshots
    prediction = build_forecast
    game.update!(start_time: prediction.generated_at - 1.minute)
    expect(game.current_prediction(ratings_config_version: version)).to be_nil
  end

  it 'excludes a forecast whose snapshot cutoff is no longer before a rescheduled Eastern date' do
    snapshots
    game.update!(start_time: 3.days.from_now)
    prediction = build_forecast
    game.update!(start_time: 1.hour.from_now)
    expect(game.current_prediction(ratings_config_version: version)).to be_nil
    expect(prediction.input_cutoff).to eq(game.schedule_date)
  end

  it 'checks rescheduled cutoff eligibility in Eastern time rather than the UTC date' do
    travel_to(Time.utc(2026, 10, 11, 16))
    game.update!(start_time: Time.utc(2026, 10, 13, 1))
    snapshots.each { |snapshot| snapshot.update!(snapshot_date: Date.new(2026, 10, 11)) }
    prediction = build_forecast
    game.update!(start_time: Time.utc(2026, 10, 12, 1)) # Still October 11 in Eastern time
    expect(prediction.input_cutoff).to eq(game.schedule_date)
    expect(game.current_prediction(ratings_config_version: version)).to be_nil
  end

  it 'aggregates one issuance using captured venue, boosts and team identity after source corrections' do
    snapshots.first.update!(home_offense_boost: 4, home_defense_boost: -3)
    game.update!(venue_type: 'home', venue_confidence: 'confirmed', neutral: false)
    first = build_forecast
    first.update!(home_offensive_efficiency_error: 30, home_defensive_efficiency_error: 20)
    snapshots.first.update!(adj_offensive_efficiency: 110)
    selected = build_forecast
    selected.update!(home_offensive_efficiency_error: 2, home_defensive_efficiency_error: -1)
    game.update!(status: :final)
    legacy = create(:prediction, game:, ratings_config_version: version,
                                 home_team_snapshot: snapshots.last, away_team_snapshot: snapshots.first,
                                 home_offensive_efficiency_error: 50, home_defensive_efficiency_error: 40)
    aggregator = ProphetRatings::TeamSeasonStatsAggregator.new(season:, ratings_config_version: version)
    aggregator.send(:preload_predictions)
    original = aggregator.send(:calculate_home_advantages, snapshots.first.team_season)
    snapshots.first.update!(home_offense_boost: 99, home_defense_boost: -99)
    game.update!(venue_type: 'neutral', neutral: true)
    aggregator.send(:preload_predictions)
    expect(aggregator.send(:calculate_home_advantages, snapshots.first.team_season)).to eq(original)
    expect(Prediction.selected_with_legacy).to contain_exactly(selected)
    expect(Prediction.selected_with_legacy).not_to include(first, legacy)
    expect(selected.forecast_home_boost(:home_offense_boost)).to eq(4)
  end

  [false, true].each do |matching_snapshots|
    it "refuses duplicate repair before mutation when frozen forecasts exist (matching snapshots: #{matching_snapshots})" do
      snapshots
      frozen_prediction = build_forecast
      duplicate = build(:game, season:, start_time: game.start_time, home_team_name: game.home_team_name,
                               away_team_name: game.away_team_name, status: :scheduled)
      duplicate.save!(validate: false) # Simulate existing imported duplicate data.
      if matching_snapshots
        create(:prediction, game: duplicate, ratings_config_version: version,
                            home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last)
      end
      original_games = Game.order(:id).map(&:attributes)
      original_predictions = Prediction.order(:id).map(&:attributes)
      repair = Maintenance::DuplicateGamesRepair.new(scope: Game.where(id: [game.id, duplicate.id]),
                                                     apply: true, output: StringIO.new)
      expect { repair.call }.to raise_error(ArgumentError, /review provenance before applying repair/)
      expect(Game.order(:id).map(&:attributes)).to eq(original_games)
      expect(Prediction.order(:id).map(&:attributes)).to eq(original_predictions)
      expect(frozen_prediction.reload).to be_persisted
    end
  end

  it 'builds a deterministic tied prediction with explicit zero deviations' do
    snapshots
    result = described_class.new(game, ratings_config_version: version).call
    expect(result).to be_persisted
    expect(result.home_win_probability).to eq(0.5)
    expect(result.margin_std_deviation).to eq(0)
    expect(result.total_std_deviation).to eq(0)
  end

  it 'skips invalid pace deviations without producing a partial prediction' do
    snapshots.first.update!(pace_volatility: -1)
    expect(described_class.new(game, ratings_config_version: version).call).to be_nil
    expect(game.predictions).to be_empty
  end

  it 'skips nonpositive expected pace without producing a prediction' do
    snapshots.each { |snapshot| snapshot.update!(adj_pace: 35) }
    expect(described_class.new(game, ratings_config_version: version).call).to be_nil
    expect(game.predictions).to be_empty
  end

  %i[offensive_efficiency_volatility defensive_efficiency_volatility pace_volatility].product([0, 1]).each do |stat, side|
    it "skips a shared-pace prediction when snapshot #{side} is missing #{stat}" do
      snapshots[side].update!(stat => nil)
      expect(described_class.new(game, ratings_config_version: version).call).to be_nil
      expect(game.predictions).to be_empty
    end
  end

  it 'retains legacy builder fallbacks for missing snapshot pace volatility' do
    payload = version.config.deep_dup
    payload['bundle_name'] = 'legacy-builder'
    payload['prediction'].delete('uncertainty_model')
    legacy = RatingsConfigVersion.publish!(payload)
    snapshots.each { |snapshot| snapshot.update!(ratings_config_version: legacy, pace_volatility: nil) }
    prediction = described_class.new(game, ratings_config_version: legacy).call
    original = [prediction.replay, prediction.margin_std_deviation, prediction.total_std_deviation]
    season.update!(efficiency_std_deviation: 40, pace_std_deviation: 30, average_efficiency: 130)
    expect(prediction).to be_persisted
    expect([prediction.replay, prediction.margin_std_deviation, prediction.total_std_deviation]).to eq(original)
  end
end
