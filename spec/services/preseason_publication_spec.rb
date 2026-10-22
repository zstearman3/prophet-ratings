# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PreseasonPublication do
  let(:season) { create(:season, average_pace: nil, average_efficiency: nil) }
  let(:model) { RatingsConfigVersion.publish! }
  let(:admin) { create(:user, :admin) }
  let!(:row) { create(:team_season, season:) }
  let(:review) { described_class.review!(season, reviewer: admin, mode: 'initialize') }

  before do
    allow(PublishPreseasonJob).to receive(:perform_later).and_return(true)
    described_class.select_model(season, model)
  end

  def queue(publication = review, acknowledge: '1', fingerprint: publication.fingerprint)
    PreseasonPublicationQueue.new(publication, actor: admin, fingerprint:, acknowledge:).call
  end

  def execute(publication = review)
    PreseasonPublicationExecution.new(publication).call
  end

  it 'requires explicit gap acknowledgement and retains its exact identity across JSONB reloads' do
    expect { queue(acknowledge: '0') }.to raise_error(ArgumentError, /acknowledge/)
    queue
    ack = review.reload.acknowledgement
    expect(ack.values_at('admin_id', 'season_id', 'model_id', 'fingerprint')).to eq([admin.id, season.id, model.id, review.fingerprint])
    expect(ack['gaps']).to eq(review.report['gaps'])
    expect(ack['acknowledged_at']).to be_present
    expect(review.status).to eq('queued')
  end

  it 'does not certify missingness when both legacy values are observed zero' do
    create(:team_offseason_profile, team_season: row, recruiting_score: 0, returning_minutes_pct: 0)
    expect(review.report['gaps']).to be_empty
    queue(acknowledge: '0')
    expect(review.reload.acknowledgement).to eq({})
  end

  it 'rejects a missing displayed fingerprint' do
    expect { queue(fingerprint: nil) }.to raise_error(ArgumentError, /identity/)
    expect(review.reload.status).to eq('review')
  end

  it 'invalidates the old selection even after selecting away and back' do
    review
    other = RatingsConfigVersion.publish!(RatingsConfigVersion.authored_config.merge(bundle_name: 'other-selection'))
    described_class.select_model(season, other)
    described_class.select_model(season, model)
    expect { queue }.to raise_error(ArgumentError, /stale/)
    expect(PreseasonPrior.count).to eq(0)
  end

  %i[profile roster dates].each do |change|
    it "rejects changed #{change} at queue and execution without rating writes" do
      queue
      case change
      when :profile then create(:team_offseason_profile, team_season: row, manual_adjustment: 2)
      when :roster then create(:team_season, season:)
      when :dates then season.update!(start_date: season.start_date + 1.day)
      end
      review.update!(status: 'review')
      expect { queue }.to raise_error(ArgumentError, /stale/)
      review.update!(status: 'queued')
      execute
      expect(review.reload.status).to eq('failed')
      expect(review.error_message).to include('stale')
      expect([PreseasonPrior.count, TeamRatingSnapshot.count, row.reload.adj_pace]).to eq([0, 0, nil])
    end
  end

  it 'publishes pinned outputs once and preserves identities on delivery and fresh safe repeats' do
    queue
    execute
    initial = review.reload.result
    expect(review.status).to eq('published')
    expect(initial['ranks']).to eq([[row.team_id, 1]])
    execute
    expect(review.reload.result).to eq(initial)
    repeated = described_class.review!(season.reload, reviewer: admin, mode: 'initialize')
    queue(repeated)
    execute(repeated)
    expect(repeated.reload.result.except('fingerprint')).to eq(initial.except('fingerprint'))
    expect([row.reload.adj_offensive_efficiency, row.adj_defensive_efficiency, row.adj_pace]).to eq([105.5, 105.5, 69.5])
  end

  it 'recovers an interrupted running operation through the same pinned review' do
    queue
    review.update!(status: 'running', started_at: 1.hour.ago)
    queue
    execute
    expect(review.reload.status).to eq('published')
    expect(PreseasonPrior.count).to eq(1)
  end

  [false, :raise].each do |failure|
    it "exposes #{failure} enqueue failure and permits explicit retry" do
      if failure == :raise
        allow(PublishPreseasonJob).to receive(:perform_later).and_raise('queue unavailable')
      else
        allow(PublishPreseasonJob).to receive(:perform_later).and_return(false)
      end
      queue
      expect(review.reload.status).to eq('failed')
      expect(review.error_message).to include('Could not enqueue')
      allow(PublishPreseasonJob).to receive(:perform_later).and_return(true)
      queue
      expect(review.reload.status).to eq('queued')
      expect(PreseasonPrior.count).to eq(0)
    end
  end

  it 'rolls back every rating write if snapshot publication fails midway' do
    queue
    snapshotter = instance_double(ProphetRatings::TeamRatingSnapshotService, call: nil)
    allow(ProphetRatings::TeamRatingSnapshotService).to receive(:new).and_return(snapshotter)
    allow(snapshotter).to receive(:call).and_raise('snapshot failed')
    execute
    expect(review.reload.status).to eq('failed')
    expect([row.reload.adj_pace, season.reload.average_pace, PreseasonPrior.count, TeamRatingSnapshot.count]).to eq([nil, nil, 0, 0])
    expect(review.error_message).to include('snapshot failed')
  end

  it 'rolls back ratings if saving the successful operation fails' do
    queue
    allow(review).to receive(:update!).and_call_original
    allow(review).to receive(:update!).with(hash_including(status: 'published')).and_raise('result failed')
    execute
    expect(review.reload.status).to eq('failed')
    expect([row.reload.adj_pace, PreseasonPrior.count, TeamRatingSnapshot.count]).to eq([nil, 0, 0])
  end

  it 'records actionable failure when a queued operation cannot acquire the ratings lock' do
    queue
    allow(Season).to receive(:with_ratings_lock).and_raise(Season::OperationInProgress, 'Another writer is running')
    execute
    expect(review.reload.status).to eq('failed')
    expect(PreseasonPrior.count).to eq(0)
  end

  it 'blocks protected outputs even if missing inputs were acknowledged' do
    queue
    season.update!(current: true)
    execute
    expect(review.reload.error_message).to include('in-season outputs')
    expect([review.status, PreseasonPrior.count, TeamRatingSnapshot.count]).to eq(['failed', 0, 0])
  end

  it 'invalidates dashboard completion when current inputs change without erasing retained results' do
    queue
    execute
    expect(PreseasonPublicationProgress.new(season.reload).call.status).to eq('complete')
    create(:team_offseason_profile, team_season: row, manual_adjustment: 2)
    expect(PreseasonPublicationProgress.new(season.reload).call.status).to eq('needs_review')
    expect(review.reload.status).to eq('published')
  end

  it 'publishes explicit new-model revisions while preserving original captures and snapshots' do
    queue
    execute
    original = [PreseasonPrior.order(:id).map(&:attributes), TeamRatingSnapshot.order(:id).map(&:attributes)]
    create(:team_offseason_profile, team_season: row, manual_adjustment: 2)
    corrected = create(:ratings_config_version)
    described_class.select_model(season, corrected)
    revision = described_class.review!(season, reviewer: admin, mode: 'revise')
    queue(revision)
    execute(revision)
    expect(revision.reload.status).to eq('published')
    expect([row.reload.adj_offensive_efficiency, row.adj_defensive_efficiency]).to eq([107.5, 103.5])
    expect([PreseasonPrior.where(ratings_config_version: model).order(:id).map(&:attributes),
            TeamRatingSnapshot.where(ratings_config_version: model).order(:id).map(&:attributes)]).to eq(original)
    expect(season.reload.preseason_revision).to eq(corrected)
  end

  it 'rejects stale duplicate queue submissions and pins worker execution to the old review model' do
    queue
    other = create(:ratings_config_version)
    described_class.select_model(season, other)
    expect { queue }.to raise_error(ArgumentError, /stale/)
    PublishPreseasonJob.perform_now(review.id)
    expect(review.reload.status).to eq('failed')
    expect([review.ratings_config_version_id, PreseasonPrior.count]).to eq([model.id, 0])
  end

  it 'preserves a live running operation when a duplicate worker cannot acquire its lock' do
    queue
    review.update!(status: 'running')
    allow(Season).to receive(:with_ratings_lock).and_raise(Season::OperationInProgress, 'Another writer is running')
    execute
    expect(review.reload.status).to eq('running')
    expect(PreseasonPrior.count).to eq(0)
  end

  it 'requeues an interrupted enqueue with its original acknowledgement and idempotent pinned execution' do
    queue
    original_ack = review.reload.acknowledgement
    retrying_admin = create(:user, :admin)
    allow(review).to receive(:verify_current).and_call_original
    PreseasonPublicationQueue.new(review, actor: retrying_admin, fingerprint: review.fingerprint, acknowledge: '0').call
    expect(PublishPreseasonJob).to have_received(:perform_later).with(review.id).twice
    expect(review.reload.acknowledgement).to eq(original_ack)
    expect(review).to have_received(:verify_current).once
    PublishPreseasonJob.perform_now(review.id)
    outputs = review.reload.result
    PublishPreseasonJob.perform_now(review.id)
    expect([review.reload.status, review.result]).to eq(['published', outputs])
    expect([PreseasonPrior.count, TeamRatingSnapshot.count]).to eq([1, 1])
  end

  it 'guards queued and worker initialization if another model was explicitly revised after preview' do
    other = create(:ratings_config_version)
    described_class.select_model(season, other)
    pending = described_class.review!(season, reviewer: admin, mode: 'initialize')
    queue(pending)
    described_class.select_model(season, model)
    revision = described_class.review!(season, reviewer: admin, mode: 'revise')
    queue(revision)
    execute(revision)
    original = row.reload.attributes
    described_class.select_model(season, other)
    expect { queue(pending) }.to raise_error(ArgumentError, /explicit.*revise/i)
    execute(pending)
    expect([pending.reload.status, pending.error_message]).to match(['failed', /explicit.*revise/i])
    expect(row.reload.attributes).to eq(original)
    expect([PreseasonPrior.where(ratings_config_version: other).count,
            TeamRatingSnapshot.where(ratings_config_version: other).count]).to eq([0, 0])
  end

  context 'with an explicit revision' do
    before do
      revision = described_class.review!(season, reviewer: admin, mode: 'revise')
      queue(revision)
      execute(revision)
    end

    it 'blocks cross-model initialize without touching outputs and permits an eligible explicit revision' do
      previous = [row.reload.attributes, PreseasonPrior.order(:id).map(&:attributes), TeamRatingSnapshot.order(:id).map(&:attributes)]
      other = create(:ratings_config_version)
      described_class.select_model(season, other)
      expect { described_class.review!(season, reviewer: admin, mode: 'initialize') }
        .to raise_error(ArgumentError, /explicit.*revise/i)
      expect([row.reload.attributes, PreseasonPrior.order(:id).map(&:attributes), TeamRatingSnapshot.order(:id).map(&:attributes)])
        .to eq(previous)
      corrected = described_class.review!(season, reviewer: admin, mode: 'revise')
      queue(corrected)
      execute(corrected)
      expect([corrected.reload.status, season.reload.preseason_revision_id]).to eq(['published', other.id])
      expect { SeasonParticipationReview.new(season).validate_revision(other) }.not_to raise_error
      expect { SeasonParticipationReview.new(season).validate_activation }.not_to raise_error
    end

    it 'retains same-model initialize repeat identities after revision' do
      previous = [PreseasonPrior.order(:id).pluck(:id), TeamRatingSnapshot.order(:id).pluck(:id)]
      queue
      execute
      expect(review.reload.status).to eq('published')
      expect([PreseasonPrior.order(:id).pluck(:id), TeamRatingSnapshot.order(:id).pluck(:id)]).to eq(previous)
      expect(season.reload.preseason_revision_id).to eq(model.id)
    end
  end

  context 'with coaching enabled' do
    let(:model) do
      config = RatingsConfigVersion.authored_config.merge(bundle_name: 'publication-coaching')
      config[:preseason][:coaching] = { formula: 'relative_pace_v2', weight: 0.5 }
      RatingsConfigVersion.publish!(config)
    end

    before { CoachingReview.create!(year: season.year, ready: true) }

    it 'invalidates a review after readiness is withdrawn and restored' do
      queue
      readiness = CoachingReview.find_by!(year: season.year)
      readiness.update!(ready: false)
      readiness.update!(ready: true)
      execute
      expect(review.reload.status).to eq('failed')
      expect(review.error_message).to include('stale')
      expect(PreseasonPrior.count).to eq(0)
    end

    it 'enforces readiness on capture reuse at queue and execution' do
      queue
      execute
      repeated = described_class.review!(season.reload, reviewer: admin, mode: 'initialize')
      expect(repeated.report['teams'].first['reuses_capture']).to be(true)
      queue(repeated)
      CoachingReview.find_by!(year: season.year).update!(ready: false)
      repeated.update!(status: 'review')
      expect { queue(repeated) }.to raise_error(ArgumentError, /not ready/)
      repeated.update!(status: 'queued')
      execute(repeated)
      expect(repeated.reload.error_message).to include('not ready')
      expect(PreseasonPrior.count).to eq(1)
    end
  end
end
