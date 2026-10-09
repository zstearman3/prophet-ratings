# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::TeamRatingSnapshotService do
  before { RatingsConfigVersion.publish! }

  it 'publishes replayable prior provenance and preserves captures across repeated snapshot writes' do
    season = create(:season, :current)
    team_season = create(:team_season, season:)
    ProphetRatings::PreseasonRatingsCalculator.new(season).call
    season.team_seasons.find_each { |team_season| team_season.update!(ratings_config_version: RatingsConfigVersion.default_version) }
    service = described_class.new(season:, as_of: season.start_date - 1)
    service.call
    snapshot = TeamRatingSnapshot.last
    captured = snapshot.stats.fetch('preseason_prior')
    expect(captured.fetch('outputs')).to eq(PreseasonPrior.last.outputs)
    expect(captured.fetch('inputs').fetch('configuration')).to eq(snapshot.ratings_config_version.config)
    service.call
    expect(snapshot.reload.stats.fetch('preseason_prior')).to eq(captured)
    expect(TeamRatingSnapshot.count).to eq(1)
    expect(team_season.reload.preseason_adj_pace).to eq(69.5)
  end

  it 'rejects a snapshot when model switching leaves values from a different capture applied' do
    season = create(:season, :current)
    team_season = create(:team_season, season:)
    config = Rails.application.config_for(:ratings).to_h.deep_symbolize_keys
    ProphetRatings::PreseasonRatingsCalculator.new(season).call
    season.team_seasons.find_each { |team_season| team_season.update!(ratings_config_version: RatingsConfigVersion.default_version) }
    changed = config.deep_dup
    changed[:bundle_name] = 'corrected'
    changed[:preseason][:fallback_efficiency] = 110
    new_version = RatingsConfigVersion.publish!(RatingsConfigVersion.authored_config.merge(changed))
    ProphetRatings::PreseasonRatingsCalculator.new(season, ratings_config_version: new_version).call
    season.team_seasons.find_each { |team_season| team_season.update!(ratings_config_version: RatingsConfigVersion.default_version) }
    service = described_class.new(season:, as_of: season.start_date - 1)
    expect { service.call }.to raise_error(ArgumentError, /selected preseason calculator/)
    expect(TeamRatingSnapshot.count).to eq(0)
    expect(team_season.reload.preseason_adj_offensive_efficiency).to eq(110)
    ProphetRatings::PreseasonRatingsCalculator.new(season).call
    season.team_seasons.find_each { |team_season| team_season.update!(ratings_config_version: RatingsConfigVersion.default_version) }
    service.call
    expect(TeamRatingSnapshot.last.stats.dig('preseason_prior', 'outputs', 'preseason_adj_offensive_efficiency')).to eq(105.5)
  end

  context 'when a later team has mismatched provenance' do
    let(:season) { create(:season, :current) }
    let!(:first_team_season) { create(:team_season, season:) }
    let!(:later_team_season) { create(:team_season, season:) }
    let(:service) { described_class.new(season:, as_of: season.start_date - 1) }

    before do
      ProphetRatings::PreseasonRatingsCalculator.new(season).call
      season.team_seasons.find_each { |team_season| team_season.update!(ratings_config_version: RatingsConfigVersion.default_version) }
    end

    it 'rolls back earlier inserts and permits a complete retry' do
      later_team_season.update!(preseason_adj_offensive_efficiency: 999)
      expect { service.call }.to raise_error(ArgumentError, /selected preseason calculator/)
      expect(TeamRatingSnapshot.count).to eq(0)
      ProphetRatings::PreseasonRatingsCalculator.new(season).call
      season.team_seasons.find_each { |team_season| team_season.update!(ratings_config_version: RatingsConfigVersion.default_version) }
      service.call
      expect(TeamRatingSnapshot.pluck(:team_season_id)).to contain_exactly(first_team_season.id, later_team_season.id)
    end

    it 'preserves existing snapshots and unrelated dates even if an outer transaction catches the failure' do
      service.call
      described_class.new(season:, as_of: season.start_date - 2).call
      original = TeamRatingSnapshot.order(:id).map(&:attributes)
      first_team_season.update!(adj_offensive_efficiency: 120)
      later_team_season.update!(preseason_adj_offensive_efficiency: 999)
      TeamRatingSnapshot.transaction(requires_new: true) do
        expect { service.call }.to raise_error(ArgumentError, /selected preseason calculator/)
        expect(TeamRatingSnapshot.order(:id).map(&:attributes)).to eq(original)
      end
    end
  end
end
