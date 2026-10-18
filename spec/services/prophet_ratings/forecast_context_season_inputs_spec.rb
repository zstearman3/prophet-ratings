# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::ForecastContext do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 10, 10, 16)) { example.run } }

  let(:season) do
    create(:season, start_date: Date.new(2026, 10, 11), end_date: Date.new(2027, 4, 10), average_pace: nil, average_efficiency: nil)
  end
  let(:teams) { Array.new(2) { create(:team_season, season:) } }
  let(:game) do
    create(:game, season:, start_time: season.start_date.in_time_zone + 12.hours, venue_type: 'neutral', status: :scheduled).tap do |record|
      teams.each_with_index { |team, index| create(:team_game, game: record, team: team.team, team_season: team, home: index.zero?) }
    end
  end

  def publish_model(name, efficiency, pace, efficiency_sd, pace_sd)
    payload = RatingsConfigVersion.authored_config.deep_dup.deep_stringify_keys
    payload['bundle_name'] = name
    payload['preseason'].merge!('fallback_efficiency' => efficiency, 'fallback_pace' => pace)
    payload['baseline_volatility'].merge!('efficiency_volatility' => efficiency_sd, 'pace_volatility' => pace_sd)
    RatingsConfigVersion.publish!(payload).tap do |version|
      ProphetRatings::PreseasonInitializer.new(season, ratings_config_version: version).call
    end
  end

  it 'issues A after B from A inputs and preserves both frozen forecasts and identical retries', :aggregate_failures do
    game
    model_a = publish_model('anchor-a', 105.5, 69.5, 11.5, 4.5)
    model_b = publish_model('anchor-b', 110, 80, 15, 6)
    expect([model_a.reload.current?, model_b.reload.current?]).to eq([false, false])
    expect(season.reload.average_pace).to eq(80)
    forecast_a = ProphetRatings::GamePredictionBuilder.new(game, ratings_config_version: model_a).call
    forecast_b = ProphetRatings::GamePredictionBuilder.new(game, ratings_config_version: model_b).call
    expect([forecast_a.pace, forecast_a.home_offensive_efficiency, forecast_a.home_score]).to eq([69.5, 105.5, 73.32])
    expect([forecast_b.pace, forecast_b.home_offensive_efficiency, forecast_b.home_score]).to eq([80, 110, 88])
    expect(forecast_a.calculation_context.fetch('season')).to eq('average_efficiency' => 105.5, 'average_pace' => 69.5,
                                                                 'efficiency_std_deviation' => 11.5, 'pace_std_deviation' => 4.5)
    expect(forecast_b.calculation_context.dig('season', 'efficiency_std_deviation')).to eq(15)
    expect(forecast_b.calculation_context.dig('season', 'pace_std_deviation')).to eq(6)
    saved = forecast_a.calculation_context.deep_dup
    replay = forecast_a.replay
    season.update!(average_pace: 90, average_efficiency: 130)
    expect(ProphetRatings::GamePredictionBuilder.new(game, ratings_config_version: model_a).call.id).to eq(forecast_a.id)
    season.team_rating_snapshots.find_each { |snapshot| snapshot.update!(adj_pace: 95) }
    teams.each { |team| team.update!(adj_pace: 99) }
    expect(forecast_a.reload.calculation_context).to eq(saved)
    expect(forecast_a.replay).to eq(replay)
  end

  it 'captures common dated model provenance on every snapshot without fresh timestamps' do
    game
    version = publish_model('anchor-a', 105.5, 69.5, 11.5, 4.5)
    inputs = season.team_rating_snapshots.map { |snapshot| snapshot.stats.fetch('season_forecast_inputs') }
    expect(inputs.uniq.size).to eq(1)
    expect(inputs.first).to include('contract_version' => 1, 'model_version_id' => version.id, 'season_id' => season.id,
                                    'snapshot_date' => '2026-10-10', 'result_cutoff' => '2026-10-10', 'source' => 'publication')
    expect(inputs.first.fetch('values')).to include('average_pace' => 69.5, 'pace_std_deviation' => 4.5)
    expect(inputs.first.fetch('value_sources').values.uniq).to eq(['season'])
    ProphetRatings::PreseasonInitializer.new(season, ratings_config_version: version).call
    expect(season.team_rating_snapshots.map { |snapshot| snapshot.stats.fetch('season_forecast_inputs') }).to eq(inputs)
  end
end
