# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PreseasonPublicationExecution do
  self.use_transactional_tests = false

  let(:season) { create(:season, year: 2098, average_pace: nil, average_efficiency: nil) }
  let(:admin) { create(:user, :admin) }
  let(:row) { create(:team_season, season:) }
  let(:model) do
    config = RatingsConfigVersion.authored_config.merge(bundle_name: 'publication-lock-fixture')
    config[:preseason][:coaching] = { formula: 'relative_pace_v2', weight: 0.5 }
    RatingsConfigVersion.publish!(config)
  end

  after do
    PreseasonPublication.where(season:).delete_all
    season.team_seasons.each { |entry| entry.update!(preseason_prior: nil) }
    PreseasonPrior.where(team_season: season.team_seasons).delete_all
    team = row.team
    season.destroy!
    team.destroy!
    CoachingReview.where(year: 2098).delete_all
    admin.destroy!
    model.destroy!
  end

  def other_connection_lock_available?
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    connection = PG.connect(config.slice(:host, :port, :password).merge(dbname: config[:database], user: config[:username]))
    connection.exec('BEGIN')
    connection.exec('SELECT pg_try_advisory_xact_lock(73127, 2098)').getvalue(0, 0) == 't'
  ensure
    connection&.exec('ROLLBACK')
    connection&.close
  end

  it 'retains the coaching transaction lock through captured reuse publication and releases it on commit' do
    row
    CoachingReview.create!(year: 2098, ready: true)
    PreseasonPublication.select_model(season, model)
    Season.with_ratings_lock { ProphetRatings::PreseasonInitializer.new(season, ratings_config_version: model).call }
    review = PreseasonPublication.review!(season.reload, reviewer: admin, mode: 'initialize')
    allow(PublishPreseasonJob).to receive(:perform_later).and_return(true)
    PreseasonPublicationQueue.new(review, actor: admin, fingerprint: review.fingerprint, acknowledge: '1').call
    expect(other_connection_lock_available?).to be(true)
    observed = []
    allow(ProphetRatings::TeamRatingSnapshotService).to receive(:new).and_wrap_original do |original, **arguments|
      service = original.call(**arguments)
      allow(service).to receive(:call).and_wrap_original do |publish|
        observed << other_connection_lock_available?
        publish.call
      end
      service
    end
    described_class.new(review).call
    expect([review.reload.status, observed]).to eq(['published', [false]])
    expect(other_connection_lock_available?).to be(true)
  end

  it 'lets an immediate worker on another connection publish after its scheduling request releases the ratings lock' do
    row
    CoachingReview.create!(year: 2098, ready: true)
    PreseasonPublication.select_model(season, model)
    review = PreseasonPublication.review!(season, reviewer: admin, mode: 'initialize')
    request_connection = ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')
    worker_connection = nil
    allow(PublishPreseasonJob).to receive(:perform_later) do |publication_id|
      worker_connection = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          pid = connection.select_value('SELECT pg_backend_pid()')
          PublishPreseasonJob.perform_now(publication_id)
          pid
        end
      end.value
      true
    end
    PreseasonPublicationQueue.new(review, actor: admin, fingerprint: review.fingerprint, acknowledge: '1').call
    expect(worker_connection).not_to eq(request_connection)
    expect([review.reload.status, review.error_message]).to eq(['published', nil])
    expect([PreseasonPrior.count, TeamRatingSnapshot.count]).to eq([1, 1])
    expect(PublishPreseasonJob).to have_received(:perform_later).with(review.id).once
  end
end
