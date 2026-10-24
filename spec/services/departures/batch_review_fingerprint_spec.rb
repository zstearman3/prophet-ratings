# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::BatchReview do
  it 'fingerprints retained content addresses without serializing the immutable source bodies again' do
    season = create(:season, year: 2026)
    batch = DepartureBatch.create!(season:, status: 'draft', plan: {})
    attempt = batch.acquisitions.build(status: 'completed', plan: {},
                                       manifest: { 'sources' => [{ 'snapshot_sha256' => 'source-hash' }] },
                                       dataset: { 'dataset_revision' => 'dataset-hash', 'production' => [] },
                                       evidence: { 'source' => { 'snapshot_base64' => 'x' * 1_000_000 } })
    review = described_class.new(batch)
    key = review.review_key(attempt:)
    attempt.evidence = { 'source' => { 'snapshot_base64' => 'different retained bytes' } }
    attempt.dataset['production'] = [{ 'large_body' => 'y' * 1_000_000 }]
    expect(review.review_key(attempt:)).to eq(key)
    attempt.dataset['dataset_revision'] = 'different-dataset-hash'
    expect(review.review_key(attempt:)).not_to eq(key)
    attempt.dataset['dataset_revision'] = 'dataset-hash'
    attempt.manifest['sources'].first['snapshot_sha256'] = 'different-source-hash'
    expect(review.review_key(attempt:)).not_to eq(key)
  end

  it 'loads the latest retained attempt at most twice during one locked publication' do
    season = create(:season, year: 2026)
    team = create(:team, school: 'Sample School')
    create(:team_season, season:, team:)
    batch = legacy_departure_batch(season)
    capture_departures(batch)
    review = save_departure_rows(batch, departure_rows(team))
    fields = { 'review_key' => review.review_key, 'confirm' => '1' }
    reads = []
    callback = lambda do |_name, _started, _finished, _unique_id, payload|
      sql = payload.fetch(:sql)
      reads << sql if sql.start_with?('SELECT') && sql.include?('"departure_acquisitions".*')
    end
    revision = ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      ActiveRecord::Base.cache { review.publish(fields, reviewer: 'admin') }
    end
    expect(revision.team_input(team.id).fetch('loss_share')).to eq(0.25)
    expect(reads.size).to be <= 2
  end

  it 'still rejects corrupted saved facts even when their declared content address is unchanged' do
    season = create(:season, year: 2026)
    team = create(:team, school: 'Sample School')
    create(:team_season, season:, team:)
    batch = legacy_departure_batch(season)
    capture_departures(batch)
    review = save_departure_rows(batch, departure_rows(team))
    attempt = batch.attempt
    attempt.dataset = attempt.dataset.merge('unretained_field' => 'corrupted saved facts')
    allow(batch).to receive(:attempt).and_return(attempt)
    expect { review.publish({ 'review_key' => review.review_key, 'confirm' => '1' }, reviewer: 'admin') }
      .to raise_error(ArgumentError, /differs from replay/)
    expect(OffseasonInputRevision.count).to eq(0)
  end
end
