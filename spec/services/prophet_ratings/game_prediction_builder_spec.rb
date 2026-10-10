# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::GamePredictionBuilder do
  let(:season) { create(:season, average_efficiency: 100, average_pace: 70) }
  let(:version) { create(:ratings_config_version) }
  let(:game) { create(:game, season:, venue_type: 'neutral') }
  let(:snapshots) do
    [true, false].map do |home|
      team = create(:team_season, season:)
      create(:team_game, game:, team: team.team, team_season: team, home:)
      create(:team_rating_snapshot, team_season: team, ratings_config_version: version,
                                    snapshot_date: game.schedule_date, adj_pace: 70,
                                    offensive_efficiency_volatility: 0, defensive_efficiency_volatility: 0, pace_volatility: 0)
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
    expect(described_class.new(game, ratings_config_version: legacy).call).to be_persisted
  end
end
