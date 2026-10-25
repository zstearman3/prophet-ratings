# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HeavyJob do
  let(:season) { create(:season, year: 2027) }

  def interrupt(job, id)
    GoodJob::CurrentThread.execution_interrupted = Time.current
    job.perform_now(id)
  ensure
    GoodJob::CurrentThread.execution_interrupted = nil
  end

  it 'fails recruiting without refetching or replacing retained captures' do
    batch = RecruitingBatch.create!(season:, source_year: 2026, status: 'fetching', snapshot_bytes: 'retained')
    allow(Recruiting::Acquisition).to receive(:new)
    interrupt(AcquireRecruitingBatchJob, batch.id)
    expect(batch.reload).to have_attributes(status: 'failed', snapshot_bytes: 'retained')
    expect(batch.failure_message).to include('interrupted')
    expect(Recruiting::Acquisition).not_to have_received(:new)
  end

  it 'fails coaching without changing readiness or importing' do
    review = CoachingReview.create!(year: 2027, discovery_status: 'fetching', ready: true)
    allow(CoachingChangesImport).to receive(:new)
    interrupt(DiscoverCoachingChangesJob, review.id)
    expect(review.reload).to have_attributes(discovery_status: 'failed', ready: true)
    expect(CoachingChangesImport).not_to have_received(:new)
  end

  it 'fails finite CBBD work without changing its budget or evidence and preserves completed work' do
    run = CbbdReviewRun.create!(season:, start_date: '2026-11-01', end_date: '2026-11-02', maximum_requests: 2, retries: 0)
    allow(Ingestion::Cbbd::Adapter).to receive(:new)
    manifest = run.manifest
    interrupt(AcquireCbbdReviewJob, run.id)
    expect(run.reload).to have_attributes(status: 'failed', maximum_requests: 2, manifest:)
    run.update!(status: 'completed')
    expect { interrupt(AcquireCbbdReviewJob, run.id) }.not_to(change { run.reload.attributes })
    expect(Ingestion::Cbbd::Adapter).not_to have_received(:new)
  end

  it 'closes only pending departure attempts while preserving evidence and approvals' do
    batch = DepartureBatch.create!(season:, plan: {}, decisions: [{ 'approved' => true }])
    attempt = batch.acquisitions.create!(status: 'running', plan: {}, evidence: { 'retained' => 'bytes' })
    allow(Departures::CbbdAcquisition).to receive(:new)
    interrupt(AcquireDepartureBatchJob, attempt.id)
    expect(attempt.reload).to have_attributes(status: 'failed', evidence: { 'retained' => 'bytes' })
    expect(batch.reload.decisions).to eq([{ 'approved' => true }])
    expect(Departures::CbbdAcquisition).not_to have_received(:new)
  end

  it 'fails preview and publication without calculating or partially publishing' do
    publication = PreseasonPublication.create!(season:, reviewer: create(:user, :admin),
                                               ratings_config_version: RatingsConfigVersion.publish!,
                                               mode: 'initialize', fingerprint: 'pinned', report: { 'evidence' => 'retained' },
                                               status: 'preview_running')
    allow(PreseasonPublicationPreview).to receive(:new)
    interrupt(PreviewPreseasonJob, publication.id)
    expect(publication.reload.status).to eq('preview_failed')
    publication.update!(status: 'running')
    interrupt(PublishPreseasonJob, publication.id)
    expect(publication.reload).to have_attributes(status: 'failed', fingerprint: 'pinned', report: { 'evidence' => 'retained' })
    expect(PreseasonPublicationPreview).not_to have_received(:new)
    expect(TeamRatingSnapshot.count).to eq(0)
    publication.update!(status: 'published')
    expect { interrupt(PublishPreseasonJob, publication.id) }.not_to(change { publication.reload.attributes })
  end
end
