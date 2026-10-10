# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SeasonParticipationReview do
  let(:season) { create(:season, year: 2027) }
  let!(:participant) { create(:team_season, season:) }
  let!(:departed) { create(:team_season, season:, adj_offensive_efficiency: 150, overall_rank: 1) }
  let(:review) { described_class.new(season) }
  let(:document) do
    {
      'evidence' => 'Synthetic authoritative roster', 'reviewed_by' => 'Test operator',
      'dates' => { 'start_date' => season.start_date.iso8601, 'end_date' => season.end_date.iso8601, 'evidence' => 'Schedule review' },
      'teams' => [
        { 'team_id' => participant.team_id, 'status' => 'included', 'reason' => 'Verified independent participant' },
        { 'team_id' => departed.team_id, 'status' => 'excluded', 'reason' => 'Verified departure' }
      ],
      'unresolved_identities' => []
    }
  end

  before do
    RatingsConfigVersion.publish!
    create(:team_alias, team: participant.team, value: participant.team.school)
  end

  def apply_review
    review.apply(document)
  end

  it 'retains legacy eligibility and does not change old outputs when a review is saved' do
    snapshot = create(:team_rating_snapshot, team_season: departed, team: departed.team, season:)
    original = [departed.attributes, snapshot.attributes]
    expect(season.rating_team_seasons).to contain_exactly(participant, departed)
    apply_review
    expect(season.rating_team_seasons).to contain_exactly(participant)
    expect([departed.reload.attributes, snapshot.reload.attributes]).to eq(original)
  end

  it 'preserves repeated review timestamps and accepts independent teams without memberships' do
    apply_review
    original = season.reload.updated_at
    apply_review
    expect(season.reload.updated_at).to eq(original)
    expect { review.validate }.not_to raise_error
    expect(TeamConference.count).to eq(0)
  end

  it 'reports omitted and explicitly unresolved team IDs and unresolved external identities' do
    historical = create(:team)
    document['teams'].first['status'] = 'unresolved'
    document['unresolved_identities'] = ['provider:new-school needs identity review']
    apply_review
    expect { review.validate }.to raise_error(ArgumentError, /#{participant.team_id}.*#{historical.id}.*provider:new-school/)
    expect { ProphetRatings::PreseasonInitializer.new(season).call }.to raise_error(ArgumentError, /unresolved/)
    expect(TeamRatingSnapshot.count).to eq(0)
  end

  it 'reports unknown IDs without treating absent standings as exclusion' do
    document['teams'] << { 'team_id' => 999_999, 'status' => 'included', 'reason' => 'Identity pending' }
    apply_review
    expect { review.validate }.to raise_error(ArgumentError, /unknown team IDs.*999999/)
  end

  it 'reports missing included rows and aliases with actionable IDs' do
    participant.destroy!
    TeamAlias.delete_all
    apply_review
    expect { review.validate }.to raise_error(ArgumentError, /season:prepare.*#{participant.team_id}.*aliases.*#{participant.team_id}/)
  end

  it 'requires reviewed dates matching the current dates separately from inherited defaults' do
    document['dates'].delete('evidence')
    apply_review
    expect { review.validate }.to raise_error(ArgumentError, %r{Review current start/end dates})
    document['dates']['evidence'] = 'Reviewed'
    apply_review
    season.update!(end_date: season.end_date + 1)
    expect { review.validate }.to raise_error(ArgumentError, %r{Review current start/end dates})
  end

  it 'rejects malformed entries or duplicate IDs before changing the prior review' do
    apply_review
    original = season.reload.participation_review
    document['teams'] << document['teams'].first.dup
    expect { apply_review }.to raise_error(ArgumentError, /Duplicate/)
    expect(season.reload.participation_review).to eq(original)
    document['teams'].pop
    document['teams'].first['reason'] = ''
    expect { apply_review }.to raise_error(ArgumentError, /reason/)
  end

  it 'publishes ranks and baselines only for included teams and preserves excluded non-rank values' do
    apply_review
    ProphetRatings::PreseasonInitializer.new(season).call
    expect([participant.reload.overall_rank, departed.reload.overall_rank]).to eq([1, nil])
    expect(departed.adj_offensive_efficiency).to eq(150)
    expect([season.reload.average_efficiency, season.avg_adj_offensive_efficiency, season.average_pace]).to eq([105.5, 105.5, 69.5])
    expect(season.team_rating_snapshots.pluck(:team_id)).to eq([participant.team_id])
    expect(season.team_rating_snapshots.first.stats['participation_key']).to eq(review.publication_key)
  end

  it 'activates using included coverage and rejects invalid pace even on a repeated activation' do
    apply_review
    expect { season.set_current! }.to raise_error(ArgumentError, /Initialize.*#{participant.team_id}/)
    ProphetRatings::PreseasonInitializer.new(season).call
    season.set_current!
    expect(season.reload).to be_current
    participant.update!(adj_pace: 0)
    expect { season.set_current! }.to raise_error(ArgumentError, /positive pace/)
  end

  it 'uses included teams for raw averages and deviations' do
    apply_review
    participant.update!(offensive_efficiency: 100, pace: 70, offensive_efficiency_std_dev: 2)
    departed.update!(offensive_efficiency: 150, pace: 90, offensive_efficiency_std_dev: 20)
    season.update_average_ratings
    expect([season.average_efficiency, season.average_pace, season.efficiency_std_deviation]).to eq([100, 70, 2])
  end

  it 'prepares a new participant without deciding their eligibility or resetting existing outputs' do
    apply_review
    ProphetRatings::PreseasonInitializer.new(season).call
    original = participant.reload.attributes
    joined = create(:team)
    SeasonPreparer.new(year: season.year).call
    expect(participant.reload.attributes).to eq(original)
    expect(season.rating_team_seasons.pluck(:team_id)).not_to include(joined.id)
    expect { review.validate }.to raise_error(ArgumentError, /unresolved.*#{joined.id}/)
  end

  it 'permits verified additions at a new publication date without overwriting historical snapshots' do
    apply_review
    ProphetRatings::PreseasonInitializer.new(season).call
    original = season.team_rating_snapshots.map(&:attributes)
    document['teams'].last['status'] = 'included'
    create(:team_alias, team: departed.team, value: departed.team.school)
    apply_review
    departed.update!(ratings_config_version: RatingsConfigVersion.default_version)
    ProphetRatings::OverallRatingsCalculator.new(season).call(as_of: season.start_date)
    expect(season.team_rating_snapshots.where(snapshot_date: season.start_date).count).to eq(2)
    expect(season.team_rating_snapshots.where(snapshot_date: season.start_date - 1).map(&:attributes)).to eq(original)
  end

  it 'refuses a changed roster behind saved predictions even at a different publication date' do
    apply_review
    ProphetRatings::PreseasonInitializer.new(season).call
    version = RatingsConfigVersion.default_version
    snapshot = season.team_rating_snapshots.first
    create(:prediction, game: create(:game, season:), ratings_config_version: version,
                        home_team_snapshot: snapshot, away_team_snapshot: snapshot)
    document['teams'].last['status'] = 'included'
    create(:team_alias, team: departed.team, value: departed.team.school)
    apply_review
    expect { ProphetRatings::OverallRatingsCalculator.new(season).call(as_of: season.start_date) }
      .to raise_error(ArgumentError, /new-version publication/)
    expect(season.team_rating_snapshots.count).to eq(1)
  end

  it 'initializes a newly verified participant using safe repeat preseason publication without forecasts' do
    apply_review
    ProphetRatings::PreseasonInitializer.new(season).call
    joined = create(:team)
    create(:team_alias, team: joined, value: joined.school)
    SeasonPreparer.new(year: season.year).call
    document['teams'] << { 'team_id' => joined.id, 'status' => 'included', 'reason' => 'Verified newly joined team' }
    apply_review
    ProphetRatings::PreseasonInitializer.new(season).call
    expect(season.team_rating_snapshots.count).to eq(2)
    expect(season.rating_team_seasons.order(:team_id).pluck(:overall_rank)).to eq([1, 2])
    expect(departed.reload.adj_offensive_efficiency).to eq(150)
  end

  it 'rejects removal at an already published date while retaining old snapshot ranks' do
    departed.update!(adj_offensive_efficiency: nil)
    document['teams'].last['status'] = 'included'
    create(:team_alias, team: departed.team, value: departed.team.school)
    apply_review
    ProphetRatings::PreseasonInitializer.new(season).call
    original = season.team_rating_snapshots.map(&:attributes)
    document['teams'].last['status'] = 'excluded'
    apply_review
    expect { ProphetRatings::PreseasonInitializer.new(season).call }.to raise_error(ArgumentError, /new-version/)
    expect(season.team_rating_snapshots.map(&:attributes)).to eq(original)
  end

  it 'continues publication when forecasts reference the new roster rather than unreferenced older snapshots' do
    apply_review
    ProphetRatings::PreseasonInitializer.new(season).call
    document['teams'].last['status'] = 'included'
    create(:team_alias, team: departed.team, value: departed.team.school)
    apply_review
    departed.update!(ratings_config_version: RatingsConfigVersion.default_version)
    calculator = ProphetRatings::OverallRatingsCalculator.new(season)
    calculator.call(as_of: season.start_date)
    pair = season.team_rating_snapshots.where(snapshot_date: season.start_date).order(:team_id)
    create(:prediction, game: create(:game, season:), ratings_config_version: RatingsConfigVersion.default_version,
                        home_team_snapshot: pair.first, away_team_snapshot: pair.last)
    expect { calculator.call(as_of: season.start_date + 1) }.not_to raise_error
    expect(season.team_rating_snapshots.where(snapshot_date: season.start_date + 1).count).to eq(2)
  end

  it 'rejects old-date republication after removal even when later predictions reference the new roster' do
    document['teams'].last['status'] = 'included'
    departed.update!(adj_offensive_efficiency: nil)
    create(:team_alias, team: departed.team, value: departed.team.school)
    apply_review
    ProphetRatings::PreseasonInitializer.new(season).call
    old_snapshots = season.team_rating_snapshots.order(:id).map(&:attributes)
    document['teams'].last['status'] = 'excluded'
    apply_review
    calculator = ProphetRatings::OverallRatingsCalculator.new(season)
    calculator.call(as_of: season.start_date)
    snapshot = season.team_rating_snapshots.find_by!(snapshot_date: season.start_date)
    create(:prediction, game: create(:game, season:), ratings_config_version: RatingsConfigVersion.default_version,
                        home_team_snapshot: snapshot, away_team_snapshot: snapshot)
    expect { calculator.publish(as_of: season.start_date - 1) }.to raise_error(ArgumentError, /new-version publication/)
    expect(season.team_rating_snapshots.where(snapshot_date: season.start_date - 1).order(:id).map(&:attributes)).to eq(old_snapshots)
  end
end
