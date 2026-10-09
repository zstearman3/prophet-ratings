# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::PreseasonRatingsCalculator, type: :service do
  before { RatingsConfigVersion.publish! }

  describe '#call' do
    let(:previous_season) do
      create(
        :season,
        year: 2025,
        start_date: Date.new(2024, 11, 1),
        end_date: Date.new(2025, 4, 10),
        average_efficiency: 106.0,
        average_pace: 69.0,
        avg_adj_offensive_efficiency: 107.0,
        avg_adj_defensive_efficiency: 104.0
      )
    end
    let(:season) do
      create(
        :season,
        :current,
        year: 2026,
        start_date: Date.new(2025, 11, 1),
        end_date: Date.new(2026, 4, 10),
        average_efficiency: 105.0,
        average_pace: 68.0
      )
    end
    let(:team) { create(:team) }
    let(:previous_team_season) do
      create(
        :team_season,
        season: previous_season,
        team: team,
        adj_offensive_efficiency: 112.0,
        adj_defensive_efficiency: 99.0,
        adj_pace: 67.0
      )
    end
    let!(:team_season) { create(:team_season, season:, team:) }
    let(:offseason_profile) do
      create(
        :team_offseason_profile,
        team_season: team_season,
        recruiting_score: 40.0,
        returning_minutes_pct: 0.8,
        manual_adjustment: 1.0
      )
    end

    before do
      previous_team_season
      offseason_profile
      described_class.new(season).call
      team_season.reload
    end

    it 'blends prior adjusted values and applies offseason adjustments for efficiency' do
      # efficiency_adjustment = (40.0 * 0.1) - (5.0 * (1.0 - 0.8)) + 1.0 = 4.0
      expect(team_season.preseason_adj_offensive_efficiency).to eq(115.25)
      expect(team_season.preseason_adj_defensive_efficiency).to eq(95.75)
    end

    it 'blends pace from prior season without offseason pace adjustment' do
      expect(team_season.preseason_adj_pace).to eq(67.3)
    end

    it 'captures source identities, values and configuration for independent replay' do
      prior = PreseasonPrior.find_by!(team_season:)
      expect(prior.inputs.dig('previous_team_season', 'id')).to eq(previous_team_season.id)
      expect(prior.inputs.dig('profile_values', 'returning_minutes_pct')).to eq(0.8)
      expect(ProphetRatings::PreseasonPriorFormula.new(prior.inputs, prior.inputs.fetch('configuration')).call).to eq(prior.outputs)
      expect { prior.update!(outputs: prior.outputs.merge('preseason_adj_pace' => 80)) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it 'preserves a prior when a new model version captures corrected inputs' do
      original = PreseasonPrior.find_by!(team_season:)
      previous_team_season.update!(adj_offensive_efficiency: 120)
      config = RatingsConfigVersion.authored_config.merge(bundle_name: 'corrected-inputs')
      version = RatingsConfigVersion.publish!(config)
      described_class.new(season, ratings_config_version: version).call
      expect(PreseasonPrior.count).to eq(2)
      expect(original.reload.outputs.fetch('preseason_adj_offensive_efficiency')).to eq(115.25)
      expect(team_season.reload.preseason_adj_offensive_efficiency).to eq(122.05)
    end

    it 'produces the same values on repeated runs' do
      keys = %w[preseason_adj_offensive_efficiency preseason_adj_defensive_efficiency preseason_adj_pace]
      expected = team_season.attributes.slice(*keys)
      described_class.new(season).call

      expect(team_season.reload.attributes.slice(*expected.keys)).to eq(expected)
    end

    it 'replays captured inputs after history and profiles change' do
      previous_team_season.update!(adj_offensive_efficiency: nil)
      offseason_profile.destroy!
      described_class.new(season).call

      expect(team_season.reload.preseason_adj_offensive_efficiency).to eq(115.25)
      expect(PreseasonPrior.count).to eq(1)
    end
  end

  it 'uses a baseline for each missing historical stat and ignores invalid legacy profile components' do
    previous = create(:season, year: 2025, avg_adj_offensive_efficiency: 107, average_pace: 69)
    season = create(:season, year: 2026)
    team_season = create(:team_season, season:)
    create(:team_season, season: previous, team: team_season.team, adj_offensive_efficiency: nil, adj_pace: 67)
    profile = TeamOffseasonProfile.new(team_season:, recruiting_score: -2, returning_minutes_pct: 80, manual_adjustment: 1)
    profile.save!(validate: false)
    described_class.new(season).call
    expect(team_season.reload.preseason_adj_offensive_efficiency).to eq(108)
    expect(team_season.preseason_adj_pace).to eq(67.3)
    expect(PreseasonPrior.last.inputs.fetch('profile_values')).to include('recruiting_score' => nil, 'returning_minutes_pct' => nil)
  end

  it 'replays the three-decimal values actually published to team seasons and snapshots' do
    previous = create(:season, year: 2025, avg_adj_offensive_efficiency: 104.666)
    season = create(:season, year: 2026)
    team_season = create(:team_season, season:)
    create(:team_season, season: previous, team: team_season.team, adj_offensive_efficiency: 111.234)
    create(:team_offseason_profile, team_season:, manual_adjustment: 1.1243, recruiting_score: nil, returning_minutes_pct: nil)
    described_class.new(season).call
    ProphetRatings::TeamRatingSnapshotService.new(season:, as_of: season.start_date - 1).call
    prior = PreseasonPrior.last
    # 104.666 * 0.15 + 111.234 * 0.85 + 1.1243 = 111.3731, published as 111.373.
    expect(prior.outputs.fetch('preseason_adj_offensive_efficiency')).to eq(111.373)
    expect(team_season.reload.preseason_adj_offensive_efficiency).to eq(111.373)
    expect(TeamRatingSnapshot.last.stats.dig('preseason_prior', 'outputs')).to eq(prior.outputs)
  end

  context 'when publication fails partway through' do
    let(:season) { create(:season, year: 2027) }

    it 'rolls back captures and values, then permits a complete retry' do
      first = create(:team_season, season:)
      second = create(:team_season, season:)
      calculator = described_class.new(season)
      allow(PreseasonPrior).to receive(:create!).and_call_original
      allow(PreseasonPrior).to receive(:create!).with(hash_including(team_season: second)).and_raise('capture failed')
      expect { calculator.call }.to raise_error('capture failed')
      expect(PreseasonPrior.count).to eq(0)
      expect(first.reload.preseason_adj_offensive_efficiency).to be_nil
      allow(PreseasonPrior).to receive(:create!).and_call_original
      calculator.call
      expect(PreseasonPrior.count).to eq(2)
    end
  end

  context 'when there is no previous season' do
    let(:season) { create(:season, :current, year: 2026) }
    let!(:team_season) { create(:team_season, season: season) }

    it 'falls back to default baselines' do
      described_class.new(season).call
      team_season.reload

      expect(team_season.preseason_adj_offensive_efficiency).to eq(105.5)
      expect(team_season.preseason_adj_defensive_efficiency).to eq(105.5)
      expect(team_season.preseason_adj_pace).to eq(69.5)
    end
  end
end
