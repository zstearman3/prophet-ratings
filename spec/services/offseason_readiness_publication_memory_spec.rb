# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OffseasonReadinessPublication do
  include ReadinessFixture

  let(:season) { create(:season) }
  let(:model) { RatingsConfigVersion.publish! }
  let(:admin) { create(:user, :admin) }
  let(:row) { create(:team_season, season:) }
  let(:publication) { described_class.new(season, model) }

  before do
    allow(PublishPreseasonJob).to receive(:perform_later).and_return(true)
    publish_readiness_fixture(season, model, row, admin)
  end

  it 'checks provenance without transferring full capture inputs or snapshot evidence' do
    statements = []
    subscriber = ->(event) { statements << event.payload[:sql] }
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      expect(publication.problems).to be_empty
      expect(publication.team_evidence.sole.fetch('capture_id')).to eq(row.reload.preseason_prior_id)
    end
    expect(statements.grep(/SELECT "preseason_priors"\.\*/)).to be_empty
    expect(statements.grep(/SELECT "team_rating_snapshots"\.\*/)).to be_empty
  end

  it 'releases captured input associations after calculating both captured and current gaps' do
    gaps = publication.gaps
    expect(gaps.pluck('source', 'kind')).to contain_exactly(
      %w[captured recruiting], %w[captured departures], %w[current recruiting], %w[current departures]
    )
    retained_rows = publication.instance_variable_get(:@rows)
    expect(retained_rows.map { |entry| entry.association(:preseason_prior).loaded? }).to all(be(false))
  end

  it 'rejects a changed captured input even when capture identity and outputs still match' do
    snapshot = season.team_rating_snapshots.sole
    stats = snapshot.stats.deep_dup
    stats.fetch('preseason_prior').fetch('inputs')['profile_values'] = { 'manual_adjustment' => 999 }
    snapshot.update!(stats:)
    expect(publication.problems).to include("Team #{row.team_id}: snapshot capture identity/values differ.")
  end

  it 'rejects a differently typed capture identity without relying on matching core columns' do
    snapshot = season.team_rating_snapshots.sole
    stats = snapshot.stats.deep_dup
    stats.fetch('preseason_prior')['id'] = row.reload.preseason_prior_id.to_s
    snapshot.update!(stats:)
    expect(publication.problems).to include("Team #{row.team_id}: snapshot capture identity/values differ.")
  end

  it 'rejects changed captured outputs without relying on matching core columns' do
    snapshot = season.team_rating_snapshots.sole
    stats = snapshot.stats.deep_dup
    stats.fetch('preseason_prior').fetch('outputs')['preseason_adj_pace'] = 999
    snapshot.update!(stats:)
    expect(publication.problems).to include("Team #{row.team_id}: snapshot capture identity/values differ.")
  end
end
