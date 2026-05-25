# frozen_string_literal: true

RSpec.describe TeamSeason do
  describe '#rank' do
    it 'uses the current persisted rank when no date is provided' do
      team_season = create(:team_season, overall_rank: 7)

      expect(team_season.rank).to eq(7)
    end

    it 'uses the latest stored rating snapshot rank as of a date' do
      team_season = create(:team_season)
      config = RatingsConfigVersion.ensure_current!
      create(:team_rating_snapshot,
             team_season:,
             ratings_config_version: config,
             snapshot_date: Date.new(2026, 1, 1),
             stats: { overall_rank: 12 })
      create(:team_rating_snapshot,
             team_season:,
             ratings_config_version: config,
             snapshot_date: Date.new(2026, 1, 2),
             stats: { overall_rank: 7 })

      expect(team_season.rank(as_of: Date.new(2026, 1, 1))).to eq(12)
    end
  end
end
