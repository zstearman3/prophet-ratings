# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::PredictionEvaluator do
  let(:season) { create(:season, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 4, 10)) }
  let(:version) { create(:ratings_config_version) }
  let(:game) do
    create(:game, season:, start_time: Time.utc(2026, 1, 3, 2), home_team_score: 80, away_team_score: 70, possessions: 90, minutes: 45)
  end
  let(:teams) { create_list(:team_season, 2, season:) }
  let(:evaluator) do
    described_class.new(ratings_config_version: version, date_range: Date.new(2026, 1, 2)..Date.new(2026, 1, 2), mode: 'legacy_unverified')
  end

  before do
    teams.each_with_index do |team, index|
      create(:team_game, game:, team_season: team, team: team.team, home: index.zero?, offensive_efficiency: index.zero? ? 100 : 90)
    end
  end

  def forecast(model = version, **attributes)
    day = attributes.delete(:snapshot_day) || Date.new(2026, 1, 1)
    snapshots = teams.map { |team| create(:team_rating_snapshot, team_season: team, ratings_config_version: model, snapshot_date: day) }
    defaults = { game:, ratings_config_version: model, home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last,
                 home_score: 84, away_score: 72, home_win_probability: 0.75, pace: 78,
                 home_offensive_efficiency: 105, away_offensive_efficiency: 88, pace_error: 999 }
    create(:prediction, **defaults, **attributes)
  end

  it 'recomputes normalized pace and efficiency errors, and reports exact scoring metrics without Gruff' do
    forecast
    allow(evaluator).to receive(:require).and_call_original
    metrics = evaluator.call
    expect(metrics).to include(games: 1, margin_mae: 2.0, total_mae: 6.0, brier_score: 0.0625)
    expect(metrics[:log_loss]).to be_within(1e-12).of(-Math.log(0.75))
    expect(metrics[:overall_mae]).to eq(pace_error_mae: 2.0, home_off_mae: 5.0, away_off_mae: 2.0)
    expect(evaluator.report.pace_pairs).to eq([[78.0, 80.0]])
    expect(evaluator).not_to have_received(:require).with('gruff')
  end

  it 'attributes the same signed pace error to both teams and uses real team IDs in the CSV' do
    forecast
    expect(evaluator.report.team_residuals.pluck(:bias)).to eq([-2.0, -2.0])
    csv = CSV.parse(evaluator.report.team_csv, headers: true)
    expect(csv.map { |row| row['team_id'].to_i }.sort).to eq(teams.map(&:team_id).sort)
    expect(csv.pluck('stddev_pace_residual')).to eq([nil, nil])
  end

  it 'keeps all calibration bins, including sparse bins and probability one' do
    forecast(home_win_probability: 1)
    expect(evaluator.report.calibration).to eq([{ lower: 0.9, upper: 1.0, games: 1, mean_probability: 1.0, observed_home_win_rate: 1.0 }])
    expect(evaluator.call[:brier_score]).to eq(0)
  end

  it 'reports impossible probabilistic forecasts as infinite log loss' do
    forecast(home_win_probability: 0)
    expect(evaluator.call[:log_loss]).to eq('Infinity')
  end

  it 'does not mix legacy records into verified pregame evaluation and handles an empty sample' do
    forecast
    verified = described_class.new(ratings_config_version: version, date_range: season.start_date..season.end_date)
    expect(verified.call[:coverage]).to include(selected: 0, evaluated: 0, available_by_kind: { 'legacy_unverified' => 1 })
    expect(verified.call[:residuals][:pace]).to eq(observations: 0, mae: nil, bias: nil, sd: nil, rmse: nil)
    expect(verified.report.pace_pairs).to be_empty
    expect(verified.report.z_histogram).to be_empty
  end

  it 'selects only one forecast per game and reports invalid selected outcomes' do
    forecast(snapshot_day: Date.new(2025, 12, 31))
    forecast(home_win_probability: nil)
    expect(evaluator.call[:coverage]).to include(selected: 1, evaluated: 0, excluded_invalid: 1)
    expect(evaluator.call[:games]).to eq(0)
  end

  it 'includes the whole Eastern end date and excludes a following game date' do
    forecast
    expect(evaluator.call[:games]).to eq(1)
    next_day = described_class.new(ratings_config_version: version, date_range: Date.new(2026, 1, 3)..Date.new(2026, 1, 3),
                                   mode: 'legacy_unverified')
    expect(next_day.call[:games]).to eq(0)
  end

  it 'compares both models on their common games only without changing forecasts' do
    forecast
    candidate = create(:ratings_config_version)
    forecast(candidate, home_score: 80, away_score: 70, home_win_probability: 0.8)
    other = described_class.new(ratings_config_version: candidate, date_range: season.start_date..season.end_date,
                                mode: 'legacy_unverified')
    comparison = nil
    expect { comparison = evaluator.compare(other) }.not_to(change { Prediction.order(:id).map(&:attributes) })
    expect(comparison[:games]).to eq(1)
    expect(comparison[:baseline][:margin_mae]).to eq(2)
    expect(comparison[:candidate][:margin_mae]).to eq(0)
  end

  it 'uses only eligible pregame revisions and derives z scores from their frozen uncertainty' do
    snapshots = teams.map do |team|
      create(:team_rating_snapshot, :with_forecast_inputs, team_season: team, ratings_config_version: version,
                                                           snapshot_date: Date.new(2026, 1, 1))
    end
    context = ProphetRatings::ForecastContext.capture(game, snapshots, version)
    [game.start_time - 2.hours, game.start_time - 1.hour, game.start_time + 1.hour].each_with_index do |time, index|
      create(:prediction, game:, ratings_config_version: version, home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last,
                          forecast_kind: 'pregame', calculation_context: context, generated_at: time, forecast_start_time: game.start_time,
                          input_cutoff: Date.new(2026, 1, 1), revision_key: "revision-#{index}",
                          home_score: 80 + index, away_score: 70, home_win_probability: 0.75, pace: 78)
    end
    verified = described_class.new(ratings_config_version: version, date_range: season.start_date..season.end_date)
    expect(verified.call[:games]).to eq(1)
    expect(verified.call[:margin_mae]).to eq(1)
    expect(verified.report.rows.first[:margin_z]).to be_positive
  end
end
