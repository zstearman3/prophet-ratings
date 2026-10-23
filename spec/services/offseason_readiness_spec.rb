# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OffseasonReadiness do
  let(:season) { create(:season) }

  it 'keeps absent model, membership and schedule evidence open without writes' do
    expect { described_class.new(season).call }.not_to change(PreseasonPrior, :count)
    report = described_class.new(season).call
    expect(report.fetch('checks').select { |check| check['hard'] }.pluck('status')).to all(eq('open'))
    expect(report.fetch('checks').find { |check| check['key'] == 'schedule' }['status']).to eq('open')
    expect(report.fetch('fingerprint')).to eq(described_class.new(season.reload).call.fetch('fingerprint'))
  end

  context 'with published evidence' do
    include ReadinessFixture

    let(:season) { create(:season) }
    let(:model) { RatingsConfigVersion.publish! }
    let(:admin) { create(:user, :admin) }
    let(:row) { create(:team_season, season:) }

    before do
      allow(PublishPreseasonJob).to receive(:perform_later).and_return(true)
      CoachingReview.create!(year: season.year, ready: true)
      publish_readiness_fixture(season, model, row, admin)
    end

    def report
      OffseasonReadiness.new(season).call
    end

    def publication
      report.fetch('checks').find { |check| check['key'] == 'publication' }
    end

    it 'verifies real applied captures and snapshots and revisits after activation without protected preview' do
      expect(report.fetch('checks').select { |check| check['hard'] }.pluck('status')).to all(eq('pass'))
      season.set_current!
      allow(PreseasonPublicationPreview).to receive(:new).and_raise('protected preview invoked')
      expect(publication.fetch('status')).to eq('pass')
      expect(report.fetch('gaps').pluck('source').uniq).to contain_exactly('current', 'captured')
    end

    it 'keeps absent optional inputs distinct from observed zero' do
      expect(report.fetch('gaps')).to be_present
      create(:team_offseason_profile, team_season: row, recruiting_score: 0, returning_minutes_pct: 0)
      expect(report.fetch('gaps').select { |gap| gap['source'] == 'current' }).to be_empty
      expect(report.fetch('gaps').select { |gap| gap['source'] == 'captured' }).to be_present
    end

    it 'rejects applied capture values that differ despite valid model identity' do
      row.update!(preseason_adj_pace: 99)
      expect(publication.fetch('status')).to eq('open')
      expect(publication.fetch('evidence').join).to include('capture outputs differ')
    end

    it 'rejects mismatching snapshot values, captured identity and ranks' do
      snapshot = season.team_rating_snapshots.sole
      snapshot.update!(adj_pace: 99, stats: snapshot.stats.merge('overall_rank' => 2, 'preseason_prior' => {}))
      expect(publication.fetch('status')).to eq('open')
      expect(publication.fetch('evidence').join).to include('identity/values differ', 'core outputs differ', 'ranks')
    end

    it 'requires retained membership decisions rather than treating legacy approval as current' do
      season.update!(participation_review: season.participation_review.except('membership_decisions'))
      expect(report.fetch('checks').find { |check| check['key'] == 'memberships' }['status']).to eq('open')
    end

    it 'keeps prediction coverage isolated to the selected model and surfaces venue unknowns' do
      game = create(:game, season:)
      other = create(:ratings_config_version)
      snapshot = create(:team_rating_snapshot, team_season: row, team: row.team, season:, ratings_config_version: other)
      create(:prediction, game:, ratings_config_version: other, home_team_snapshot: snapshot, away_team_snapshot: snapshot,
                          home_win_probability: 0.5)
      checks = report.fetch('checks').index_by { |check| check['key'] }
      expect(checks.fetch('predictions').fetch('evidence')).to include('0 of 1')
      expect(checks.fetch('venues').fetch('status')).to eq('open')
    end

    it 'reports scoped failed operations without copying source bytes into displayed evidence' do
      RecruitingBatch.create!(season:, source_year: season.year - 1, status: 'failed', failure_message: 'Source unavailable',
                              extract_bytes: 'private raw source')
      operations = report.fetch('checks').find { |check| check['key'] == 'operations' }
      expect(operations.fetch('evidence').to_json).to include('Source unavailable')
      expect(operations.fetch('evidence').to_json).not_to include('private raw source')
    end

    context 'when the selected contract requires coaching' do
      let(:model) do
        payload = RatingsConfigVersion.authored_config.deep_dup
        payload[:bundle_name] = 'readiness-coaching'
        payload[:preseason][:coaching] = { formula: 'relative_pace_v2', weight: 0.5 }
        RatingsConfigVersion.publish!(payload)
      end

      before { CoachingReview.find_by!(year: season.year).update!(ready: false) }

      it 'retains captured gaps and a scoped current-source error in fresh acknowledgements when coaching is unready' do
        gaps = report.fetch('gaps')
        expect(gaps.select { |gap| gap['source'] == 'captured' }.pluck('kind')).to contain_exactly('recruiting', 'departures')
        expect(gaps.find { |gap| gap['kind'] == 'inputs' }).to include('source' => 'current', 'team_id' => row.team_id)
        expect(save_readiness_review(season, admin).acknowledgement['gaps']).to eq(gaps)
      end

      it 'keeps applicable coaching hard and rejects activation even with optional acknowledgement' do
        checks = report.fetch('checks').index_by { |check| check['key'] }
        expect(checks.fetch('coaching')).to include('hard' => true, 'status' => 'open')
        review = save_readiness_review(season, admin)
        expect { OffseasonReadinessActivation.new(review, actor: admin, action: 'season').call }
          .to raise_error(ArgumentError, /required readiness/)
        expect(season.reload).not_to be_current
      end
    end
  end
end
