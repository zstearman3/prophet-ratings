# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::SeasonForecastInputs do
  let(:version) { create(:ratings_config_version) }
  let(:season) { create(:season, average_efficiency: 100, average_pace: 70) }
  let(:date) { Date.new(2026, 10, 10) }
  let(:game) { create(:game, season:, start_time: (date + 1).in_time_zone + 12.hours, venue_type: 'neutral') }
  let(:snapshots) do
    [true, false].map do |home|
      participant = create(:team_season, season:, ratings_config_version: version)
      create(:team_game, game:, team: participant.team, team_season: participant, home:)
      create(:team_rating_snapshot, :with_forecast_inputs, team_season: participant, snapshot_date: date, ratings_config_version: version)
    end
  end

  def capture
    ProphetRatings::ForecastContext.capture(game, snapshots, version)
  end

  it 'uses all four saved inputs even if live season fields are missing' do
    snapshots
    season.update!(average_pace: nil, average_efficiency: nil, efficiency_std_deviation: nil, pace_std_deviation: nil)
    expect(capture.fetch('season')).to eq('average_efficiency' => 100, 'average_pace' => 70,
                                          'efficiency_std_deviation' => 1, 'pace_std_deviation' => 1)
  end

  it 'captures configured fallbacks explicitly and preserves zero deviations' do
    season.assign_attributes(average_efficiency: nil, average_pace: nil, efficiency_std_deviation: nil, pace_std_deviation: 0)
    inputs = described_class.capture(season, version, date)
    expect(inputs.fetch('values')).to eq('average_efficiency' => 105, 'average_pace' => 70,
                                         'efficiency_std_deviation' => 11.5, 'pace_std_deviation' => 0)
    expect(inputs.fetch('value_sources')).to eq('average_efficiency' => 'config.defaults.season_defaults.average_efficiency',
                                                'average_pace' => 'config.defaults.season_defaults.average_pace',
                                                'efficiency_std_deviation' => 'config.baseline_volatility.efficiency_volatility',
                                                'pace_std_deviation' => 'season')
  end

  it 'rejects prepared participants and snapshots from a different game season' do
    snapshots
    game.season = create(:season, year: 2025)
    expect { capture }.to raise_error(ArgumentError, /game season/)
  end

  it 'rejects metadata-free legacy snapshots for new issuance with a republishing explanation' do
    snapshots.first.stats.delete('season_forecast_inputs')
    expect { capture }.to raise_error(ArgumentError, /republish ratings/)
  end

  it 'rejects each incompatible publication metadata field' do
    original_stats = snapshots.first.stats.deep_dup
    {
      'contract_version' => 2, 'model_version_id' => -1, 'season_id' => -1,
      'snapshot_date' => '2026-10-09', 'result_cutoff' => '2026-10-09', 'source' => 'reconstruction',
      'values' => {}, 'value_sources' => {}
    }.each do |field, invalid|
      aggregate_failures "incompatible #{field} metadata" do
        snapshots.first.stats = original_stats.deep_dup
        snapshots.first.stats['season_forecast_inputs'][field] = invalid
        expect { capture }.to raise_error(ArgumentError, /season forecast inputs|Season forecast inputs/)
      end
    end
  end

  it 'rejects each invalid saved mean and deviation' do
    original_stats = snapshots.first.stats.deep_dup
    %w[average_efficiency average_pace efficiency_std_deviation pace_std_deviation].each do |field|
      [nil, Float::INFINITY, Float::NAN, -1].each do |invalid|
        aggregate_failures "invalid #{field}=#{invalid.inspect}" do
          snapshots.first.stats = original_stats.deep_dup
          snapshots.first.stats['season_forecast_inputs']['values'][field] = invalid
          expect { capture }.to raise_error(ArgumentError, /finite positive means/)
        end
      end
    end
  end

  it 'rejects nonpositive means at publication before any rows can be saved' do
    [0, -1, Float::INFINITY].each do |value|
      season.average_pace = value
      expect { described_class.capture(season, version, date) }.to raise_error(ArgumentError, /finite positive means/)
    end
  end

  it 'rejects different saved values and source evidence even when each side is independently valid' do
    saved = snapshots.first.stats['season_forecast_inputs']
    saved['values']['average_pace'] = 80
    expect { capture }.to raise_error(ArgumentError, /must match across both/)
    saved['values']['average_pace'] = 70
    saved['value_sources']['average_pace'] = 'config.defaults.season_defaults.average_pace'
    expect { capture }.to raise_error(ArgumentError, /must match across both/)
  end

  it 'rejects individually valid publications with different snapshot dates' do
    snapshots.last.snapshot_date = date - 1
    snapshots.last.stats['season_forecast_inputs'] = described_class.capture(season, version, date - 1)
    expect { capture }.to raise_error(ArgumentError, /must match across both/)
  end

  it 'rejects game-day or later publication cutoffs' do
    game.start_time = date.in_time_zone + 12.hours
    snapshots
    expect { capture }.to raise_error(ArgumentError, /precede the Eastern game date/)
  end

  it 'rejects a persisted publication paired with matching ephemeral working inputs' do
    snapshots
    reconstructed = ProphetRatings::HistoricalRatingsState.snapshot(snapshots.last.team_season, date)
    expect(reconstructed.stats.dig('season_forecast_inputs', 'values')).to eq(snapshots.first.stats.dig('season_forecast_inputs', 'values'))
    snapshots[1] = reconstructed
    expect { capture }.to raise_error(ArgumentError, /must match across both/)
  end

  it 'rejects each snapshot identity mismatch' do
    identity_fields = %w[team_id team_season_id season_id ratings_config_version_id]
    original_identity = snapshots.first.attributes.slice(*identity_fields)
    identity_fields.each do |field|
      aggregate_failures "snapshot identity mismatch in #{field}" do
        snapshots.first.assign_attributes(original_identity)
        snapshots.first.public_send("#{field}=", -1)
        expect { capture }.to raise_error(ArgumentError, /selected model, season and game participant/)
      end
    end
  end

  it 'labels ephemeral reconstruction inputs without claiming publication provenance' do
    pair = snapshots.map { |snapshot| ProphetRatings::HistoricalRatingsState.snapshot(snapshot.team_season, date) }
    context = ProphetRatings::ForecastContext.capture(game, pair, version)
    expect(context.dig('season_source', 'source')).to eq('reconstruction')
    expect(context.fetch('snapshots').map { |inputs| inputs.dig('source', 'id') }).to eq([nil, nil])
  end

  it 'still replays a literal old frozen contract without publication metadata' do
    context = {
      'contract_version' => 1, 'model_version_id' => version.id, 'model_config' => version.config,
      'season_id' => season.id, 'season_source' => { 'id' => season.id },
      'season' => { 'average_efficiency' => 100, 'average_pace' => 70, 'efficiency_std_deviation' => 1, 'pace_std_deviation' => 1 },
      'venue' => { 'venue_type' => 'neutral', 'venue_confidence' => 'confirmed' }, 'upset_modifier' => 1.0,
      'snapshots' => [1, 2].map do |team_id|
        { 'source' => { 'team_id' => team_id, 'snapshot_date' => '2026-10-10' }, 'school' => "School #{team_id}",
          'ratings' => { 'adj_offensive_efficiency' => 100, 'adj_defensive_efficiency' => 100, 'adj_pace' => 70 },
          'stats' => { 'offensive_efficiency_volatility' => 0, 'defensive_efficiency_volatility' => 0, 'pace_volatility' => 0,
                       'home_offense_boost' => 0, 'home_defense_boost' => 0 } }
      end
    }
    result = ProphetRatings::ForecastContext.new(context).predictor.call
    expect(result.values_at(:home_expected_score, :away_expected_score, :win_probability_home)).to eq([70, 70, 0.5])
    expect(context.fetch('season_source')).to eq('id' => season.id)
  end
end
