# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::PredictionComparisonReport do
  let(:season) { create(:season, year: 2026, start_date: Date.new(2025, 11, 1), end_date: Date.new(2026, 4, 10)) }
  let(:baseline) { create(:ratings_config_version) }
  let(:candidate) { create(:ratings_config_version) }
  let(:teams) { create_list(:team_season, 2, season:) }
  let(:report) do
    described_class.new(season:, baseline:, candidate:, baseline_mode: 'legacy_unverified', candidate_mode: 'reconstruction')
  end

  def game_on(date = season.start_date)
    game = create(:game, season:, start_time: Game.schedule_time_for(date) + 12.hours,
                         home_team_score: 80, away_team_score: 70, possessions: 90, minutes: 45)
    teams.each_with_index do |team, index|
      create(:team_game, game:, team_season: team, team: team.team, home: index.zero?, offensive_efficiency: 100)
    end
    game
  end

  def forecast(game, version, **attributes)
    snapshots = teams.map do |team|
      create(:team_rating_snapshot, :with_forecast_inputs, team_season: team, ratings_config_version: version,
                                                           snapshot_date: game.schedule_date - 1)
    end
    values = { game:, ratings_config_version: version, home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last,
               home_score: 84, away_score: 72, home_win_probability: 0.75, pace: 78,
               home_offensive_efficiency: 105, away_offensive_efficiency: 98, pace_error: 999 }
    if version == candidate
      values.merge!(forecast_kind: 'reconstruction', calculation_context: ProphetRatings::ForecastContext.capture(game, snapshots, version),
                    generated_at: Time.current, forecast_start_time: game.start_time, input_cutoff: game.schedule_date - 1,
                    revision_key: SecureRandom.hex)
    end
    create(:prediction, **values, **attributes)
  end

  it 'compares different forecast types on common valid games, preserving records' do
    common = game_on
    forecast(common, baseline)
    forecast(common, candidate, home_score: 79, away_score: 73, home_win_probability: 0.5)
    forecast(game_on(season.start_date + 1), baseline, home_score: 999)
    original = Prediction.order(:id).map(&:attributes)

    metrics = report.comparison
    expect(metrics[:games]).to eq(1)
    expect(metrics[:baseline]).to include(margin_mae: 2.0, total_mae: 6.0, brier_score: 0.0625)
    expect(metrics[:candidate]).to include(margin_mae: 4.0, total_mae: 2.0, brier_score: 0.25)
    expect(report.text).to include('Illustrative only', baseline.name, candidate.name, 'Common valid games: 1', 'legacy_unverified')
    expect(Prediction.order(:id).map(&:attributes)).to eq(original)
  end

  it 'exports paired absolute errors and exact probability losses with source identities' do
    game = game_on
    old = forecast(game, baseline)
    fresh = forecast(game, candidate, home_score: 79, away_score: 73, home_win_probability: 0)
    rows = CSV.parse(report.csv, headers: true)
    expect(rows.size).to eq(2)
    expect(rows.first.to_h).to include('game_id' => game.id.to_s, 'model' => baseline.name, 'prediction_id' => old.id.to_s,
                                       'margin_absolute_error' => '2.0', 'total_absolute_error' => '6.0',
                                       'pace_absolute_error' => '2.0', 'home_efficiency_absolute_error' => '5.0',
                                       'away_efficiency_absolute_error' => '2.0', 'brier_score' => '0.0625')
    expect(rows[1].to_h).to include('prediction_id' => fresh.id.to_s, 'forecast_type' => 'reconstruction', 'log_loss' => 'Infinity')
    expect(rows.first['log_loss'].to_f).to be_within(1e-12).of(-Math.log(0.75))
  end

  it 'reports no common games as unavailable metrics and a header-only CSV' do
    forecast(game_on, baseline)
    expect(report.comparison[:games]).to eq(0)
    expect(report.text).to include('Common valid games: 0', 'N/A', 'No common valid games')
    expect(CSV.parse(report.csv, headers: true)).to be_empty
  end

  it 'rejects reversed dates and dates outside the selected season' do
    expect do
      described_class.new(season:, baseline:, candidate:, from: '2025-12-01', through: '2025-11-01')
    end.to raise_error(ArgumentError, /date range/)
    expect do
      described_class.new(season:, baseline:, candidate:, from: '2025-10-31')
    end.to raise_error(ArgumentError, /date range/)
  end

  it 'honors Eastern date bounds and excludes invalid forecasts from both metrics and CSV' do
    game = game_on
    forecast(game, baseline, home_win_probability: nil)
    forecast(game, candidate)
    later = game_on(season.start_date + 1)
    forecast(later, baseline)
    forecast(later, candidate)
    limited = described_class.new(season:, baseline:, candidate:, through: season.start_date.iso8601)
    expect(limited.comparison[:games]).to eq(0)
    expect(limited.text).to include('excluded_invalid=1')
    expect(CSV.parse(limited.csv, headers: true)).to be_empty
  end

  describe 'command line' do
    def run_script(*arguments)
      original = ARGV.dup
      ARGV.replace(arguments)
      load Rails.root.join('script/compare_model_predictions.rb')
    ensure
      ARGV.replace(original)
    end

    def command_arguments
      ['--year', season.year.to_s, '--baseline', baseline.name, '--candidate', candidate.name]
    end

    it 'prints a paired report and writes the requested per-game CSV' do
      game = game_on
      forecast(game, baseline)
      forecast(game, candidate)
      Tempfile.create(['prediction-comparison', '.csv']) do |file|
        expect { run_script(*command_arguments, '--csv', file.path) }.to output(/Common valid games: 1/).to_stdout
        expect(CSV.read(file.path, headers: true).size).to eq(2)
      end
    end

    it 'allows independent forecast types and reports an empty comparison when they do not match saved rows' do
      game = game_on
      forecast(game, baseline)
      forecast(game, candidate)
      expect do
        run_script(*command_arguments, '--baseline-mode', 'reconstruction', '--candidate-mode', 'legacy_unverified')
      end.to output(/No common valid games/).to_stdout
    end

    it 'fails with a clear message for missing arguments and invalid forecast types' do
      expect do
        expect { run_script('--year', '2026') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(/Required options: baseline, candidate/).to_stderr
      expect do
        expect { run_script(*command_arguments, '--candidate-mode', 'typo') }.to raise_error(SystemExit)
      end.to output(/Unknown forecast type/).to_stderr
    end
  end
end
