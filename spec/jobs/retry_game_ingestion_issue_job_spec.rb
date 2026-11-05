# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RetryGameIngestionIssueJob do
  include_context 'with scoring review evidence'
  include ActiveJob::TestHelper

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  def missing_issue
    invalid = row.deep_dup.merge('source_completed' => false, 'completion_evidence' => nil,
                                 'reasons' => ['source not confirmed final with unequal valid scores'])
    report = Ingestion::HistoricalSyncObservation.new(invalid, season).call
    GameIngestionIssue.find(report[:issue_ids].sole)
  end

  it 'pins one finite acquisition after lookback expiry and imports only the selected source', :aggregate_failures do
    issue = missing_issue
    calls = []
    fixture['games'] << source_game.deep_dup.merge('id' => 999)
    allow(Ingestion::Cbbd::HttpTransport).to receive(:call) do |uri, _key|
      calls << uri.path
      { status: 200, headers: {}, body: fixture.fetch(uri.path == '/games' ? 'games' : 'boxes').to_json }
    end
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('CBBD_API_KEY', '').and_return('synthetic')
    retry_service = Ingestion::GameIssueRetry.new(issue:, user: admin, fingerprint: issue.comparison_fingerprint)
    job_id = retry_service.enqueue
    expect(retry_service.enqueue).to eq(job_id)
    acquisition = issue.reload.retry_acquisition
    expect(acquisition).to have_attributes(start_date: date, end_date: date, maximum_requests: 50, retries: 2)
    described_class.new.perform(issue.id, acquisition.id)
    expect(issue.reload.retry_status).to eq('completed')
    expect(Game.sole).to be_final
    expect(GameExternalIdentity.sole.external_id).to eq('1')
    described_class.new.perform(issue.id, acquisition.id)
    expect(calls).to eq(['/games', '/games/teams'])
  end

  it 'rejects stale retry intent without enqueuing another acquisition' do
    issue = missing_issue
    service = Ingestion::GameIssueRetry.new(issue:, user: admin, fingerprint: 'stale')
    expect { service.enqueue }.to raise_error(ArgumentError, /changed|reload/i)
    expect(CbbdReviewRun.count).to eq(0)
  end
end
