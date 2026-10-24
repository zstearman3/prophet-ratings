# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PreseasonPublication do
  let(:season) { create(:season, average_pace: nil, average_efficiency: nil) }
  let(:model) { RatingsConfigVersion.publish! }
  let(:admin) { create(:user, :admin) }
  let!(:row) { create(:team_season, season:) }

  before do
    described_class.select_model(season, model)
    allow(PreviewPreseasonJob).to receive(:perform_later).and_return(true)
    allow(PublishPreseasonJob).to receive(:perform_later).and_return(true)
  end

  def request_preview
    described_class.review!(season, reviewer: admin, mode: 'initialize')
  end

  it 'persists a pinned pending request without calculating ratings' do
    allow(PreseasonPublicationPreview).to receive(:new).and_call_original
    publication = request_preview
    expect(publication.status).to eq('preview_queued')
    expect(PreseasonPublicationPreview).not_to have_received(:new)
    expect(publication.report['selection_generation']).to eq(season.preseason_selection_generation)
    expect(PreviewPreseasonJob).to have_received(:perform_later).with(publication.id)
  end

  it 'builds a read-only review once and preserves it on duplicate preview delivery' do
    publication = request_preview
    PreviewPreseasonJob.perform_now(publication.id)
    expect(publication.reload.status).to eq('review')
    original = publication.attributes
    PreviewPreseasonJob.perform_now(publication.id)
    expect(publication.reload.attributes).to eq(original)
    expect(publication.report['teams'].first['team_id']).to eq(row.team_id)
    expect(PreseasonPrior.count).to eq(0)
  end

  it 'fails a preview after selecting away and back without silently repinning it' do
    publication = request_preview
    other = create(:ratings_config_version)
    described_class.select_model(season, other)
    described_class.select_model(season, model)
    PreviewPreseasonJob.perform_now(publication.id)
    expect(publication.reload.status).to eq('preview_failed')
    expect(publication.error_message).to include('selection')
    expect(publication.report['teams']).to be_nil
  end

  it 'persists calculation failures and never permits an unfinished proposal to publish' do
    publication = request_preview
    row.destroy!
    PreviewPreseasonJob.perform_now(publication.id)
    expect(publication.reload.status).to eq('preview_failed')
    expect(publication.error_message).to include('No included teams')
    expect do
      PreseasonPublicationQueue.new(publication, actor: admin, fingerprint: publication.fingerprint, acknowledge: '1').call
    end.to raise_error(ArgumentError, /preview/i)
    expect(PreseasonPrior.count).to eq(0)
  end

  it 'does not calculate on publish submission but rejects stale evidence in the worker' do
    publication = request_preview
    PreviewPreseasonJob.perform_now(publication.id)
    publication.reload
    create(:team_offseason_profile, team_season: row, manual_adjustment: 2)
    allow(publication).to receive(:verify_current).and_call_original
    PreseasonPublicationQueue.new(publication, actor: admin, fingerprint: publication.fingerprint, acknowledge: '1').call
    expect(publication).not_to have_received(:verify_current)
    PublishPreseasonJob.perform_now(publication.id)
    expect(publication.reload.status).to eq('failed')
    expect(publication.error_message).to include('stale')
    expect(PreseasonPrior.count).to eq(0)
  end

  it 'persists enqueue failure and allows retry of the same pinned preview' do
    allow(PreviewPreseasonJob).to receive(:perform_later).and_return(false)
    publication = request_preview
    expect(publication.status).to eq('preview_failed')
    expect(publication.error_message).to include('Could not enqueue preview')
    allow(PreviewPreseasonJob).to receive(:perform_later).and_return(true)
    PreseasonPublicationPreviewQueue.new(publication).call
    PreviewPreseasonJob.perform_now(publication.id)
    expect(publication.reload.status).to eq('review')
  end

  it 'ignores an unqueued publication delivery and preserves a failed preview' do
    publication = request_preview
    PublishPreseasonJob.perform_now(publication.id)
    expect(publication.reload.status).to eq('preview_queued')
    publication.update!(status: 'preview_failed', error_message: 'Retained error')
    PublishPreseasonJob.perform_now(publication.id)
    expect([publication.reload.status, publication.error_message]).to eq(['preview_failed', 'Retained error'])
    expect(PreseasonPrior.count).to eq(0)
  end
end
