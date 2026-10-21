# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin CBBD identity review', type: :request do
  include Devise::Test::IntegrationHelpers

  include_context 'with synthetic reconciliation'

  let(:admin) { create(:user, admin: true) }
  let(:run) do
    value = CbbdReviewRun.create!(season:, start_date: '2025-11-01', end_date: '2025-11-02', maximum_requests: 4, retries: 0,
                                  status: 'completed', manifest: { 'finalized' => true, 'acquisition' => { 'captures' => [] } },
                                  normalized_replay: replay)
    value.update!(evidence_digest: value.evidence_hash)
    value
  end

  around do |example|
    adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = adapter
  end

  def review_queries(&)
    queries = []
    subscriber = lambda do |*, payload|
      sql = payload.fetch(:sql)
      queries << sql if sql.start_with?('SELECT') && sql.include?('cbbd_review_')
    end
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record', &)
    queries
  end

  it 'guards every endpoint with the existing admin session' do
    get admin_cbbd_review_runs_path
    expect(response).to redirect_to(new_user_session_path)
    sign_in create(:user, admin: false)
    [[:get, admin_cbbd_review_runs_path], [:get, admin_cbbd_review_run_path(run)],
     [:post, admin_cbbd_review_runs_path], [:post, compare_admin_cbbd_review_run_path(run)],
     [:patch, admin_cbbd_review_run_path(run)], [:post, apply_admin_cbbd_review_run_path(run)]].each do |method, path|
      public_send(method, path)
      expect(response).to redirect_to(root_path)
    end
  end

  it 'queues explicit bounded acquisition without exposing credentials or importing' do
    sign_in admin
    expect do
      post admin_cbbd_review_runs_path, params: { season_id: season.id, start_date: '2025-11-01', end_date: '2025-11-02',
                                                  maximum_requests: '4', retries: '0', api_key: 'untrusted' }
    end.to have_enqueued_job(AcquireCbbdReviewJob)
    expect(CbbdReviewRun.last).to have_attributes(maximum_requests: 4, status: 'queued')
    expect(Game.count).to eq(0)
  end

  it 'renders evidence, saves real indexed browser rows across sections and applies as signed-in actor' do
    sign_in admin
    game
    post compare_admin_cbbd_review_run_path(run)
    comparison = run.reload.active_comparison
    get admin_cbbd_review_run_path(run)
    expect(response.body).to include('Source observations', 'Save visible draft', 'Shadow', 'Synthetic Home')
    choices.each_with_index do |choice, index|
      patch admin_cbbd_review_run_path(run), params: {
        review: { comparison_id: comparison.id, draft_revision: comparison.reload.draft_revision,
                  rows: { index.to_s => choice.merge(selected: '1', deferred: '0', supersedes_external_id: '') } }
      }
      expect(response).to have_http_status(:redirect), response.body
    end
    # Real unchecked checkbox sends hidden 0; other pages remain approved.
    patch admin_cbbd_review_run_path(run), params: {
      review: { comparison_id: comparison.id, draft_revision: comparison.reload.draft_revision,
                rows: { '0' => choices.last.merge(selected: '0', deferred: '1') } }
    }
    expect(comparison.reload.draft.values.count { |row| row['selected'] }).to eq(2)
    post apply_admin_cbbd_review_run_path(run), params: {
      review: { comparison_id: comparison.id, draft_revision: comparison.draft_revision, confirm: '1',
                reason: 'Checked private evidence', reviewer: 'forged' }
    }
    expect(response).to have_http_status(:redirect)
    expect(IdentityMappingDecision.last.reviewer).to eq("User #{admin.id}: #{admin.email}")
    expect(GameExternalIdentity.count).to eq(0)
    get admin_cbbd_review_run_path(run)
    expect(response.body).to include('Checked private evidence', admin.email, 'Refresh comparison')
    get admin_cbbd_review_run_path(run, entity: 'shadow', status: 'unresolved_evidence')
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Source / local values and evidence', 'unresolved_evidence')
  end

  it 'rejects cross-run versions and stale browser submissions' do
    sign_in admin
    comparison = Ingestion::Reconciliation::RunReview.new(run).compare
    other = CbbdReviewRun.create!(season:, start_date: run.start_date, end_date: run.end_date, maximum_requests: 2, retries: 0)
    patch admin_cbbd_review_run_path(other), params: { review: { comparison_id: comparison.id, draft_revision: 0 } }
    expect(response).to have_http_status(:not_found)
    sign_in admin
    patch admin_cbbd_review_run_path(run), params: { review: { comparison_id: comparison.id, draft_revision: 99 } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'rejects non-strict or out-of-season acquisition dates without queueing work' do
    sign_in admin
    %w[2025-11-1 2024-11-01].each do |date|
      expect do
        post admin_cbbd_review_runs_path, params: { season_id: season.id, start_date: date, end_date: '2025-11-02',
                                                    maximum_requests: '4', retries: '0' }
      end.not_to change(CbbdReviewRun, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  it 'acquires and reopens durable nonempty evidence from a queued job using only server credentials' do
    sign_in admin
    game
    responses = [fixture['games'], fixture['boxes']]
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('CBBD_API_KEY', '').and_return('private-synthetic-key')
    allow(Ingestion::Cbbd::HttpTransport).to receive(:call) do |*|
      { status: 200, body: responses.shift.to_json, headers: {} }
    end
    post admin_cbbd_review_runs_path, params: { season_id: season.id, start_date: '2025-11-01', end_date: '2025-11-02',
                                                maximum_requests: '4', retries: '0' }
    value = CbbdReviewRun.last
    AcquireCbbdReviewJob.perform_now(value.id)
    expect(value.reload.status).to eq('completed')
    expect(value.captures.count).to eq(2)
    post compare_admin_cbbd_review_run_path(value)
    get admin_cbbd_review_run_path(CbbdReviewRun.find(value.id), entity: 'game')
    expect(response.body).to include('Synthetic Home', 'Source observations', 'Approve mapping')
    expect([TeamExternalIdentity.count, GameExternalIdentity.count, IdentityMappingDecision.count]).to eq([0, 0, 0])
  end

  it 'denies generic RailsAdmin inspection, creation, mutation and export for every private review model' do
    comparison = Ingestion::Reconciliation::RunReview.new(run).compare
    capture = run.captures.create!(capture_id: 'private-synthetic', body: '[]', metadata: {})
    records = { 'cbbd_review_run' => run, 'cbbd_review_capture' => capture, 'cbbd_review_comparison' => comparison }
    before = records.values.map(&:attributes)
    records.each do |model, record|
      [[:get, "/admin/#{model}"], [:get, "/admin/#{model}/new"], [:get, "/admin/#{model}/export"],
       [:get, "/admin/#{model}/#{record.id}"], [:get, "/admin/#{model}/#{record.id}/edit"],
       [:post, "/admin/#{model}/new"], [:put, "/admin/#{model}/#{record.id}/edit"],
       [:delete, "/admin/#{model}/#{record.id}/delete"]].each do |method, path|
        sign_in admin
        public_send(method, path, params: { model => record.attributes.except('id', 'created_at', 'updated_at') })
        expect([403, 404]).to include(response.status), "#{method} #{path}: #{response.status}"
      end
    end
    expect(records.values.map { |record| record.reload.attributes }).to eq(before)
    expect([CbbdReviewRun.count, CbbdReviewCapture.count, CbbdReviewComparison.count]).to eq([1, 1, 1])
    sign_in admin
    get "/admin/cbbd_review_runs/#{run.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Save visible draft', 'Apply saved approvals')
  end

  it 'cannot adopt a hidden generic-admin approval when applying an unchanged empty-draft browser token' do
    game
    comparison = Ingestion::Reconciliation::RunReview.new(run).compare
    sign_in admin
    put "/admin/cbbd_review_comparison/#{comparison.id}/edit", params: {
      cbbd_review_comparison: { draft: { 'team:10' => choices.first.merge('selected' => true, 'deferred' => false) }.to_json }
    }
    denied_status = response.status
    sign_in admin
    post "/admin/cbbd_review_runs/#{run.id}/apply", params: {
      review: { comparison_id: comparison.id, draft_revision: 0, confirm: '1', reason: 'Previously reviewed empty draft' }
    }
    expect([denied_status, response.status]).to eq([403, 422]), response.body
    expect(comparison.reload).to have_attributes(draft: {}, draft_revision: 0)
    expect([TeamExternalIdentity.count, GameExternalIdentity.count, IdentityMappingDecision.count]).to eq([0, 0, 0])
  end

  it 'renders projected run and version summaries in order while loading the full chosen artifact' do
    sign_in admin
    game
    review = Ingestion::Reconciliation::RunReview.new(run)
    applied = review.compare
    review.save('comparison_id' => applied.id, 'draft_revision' => 0,
                'rows' => [choices.first.merge('selected' => '1')])
    review.apply({ 'comparison_id' => applied.id, 'draft_revision' => 1, 'confirm' => '1', 'reason' => 'Synthetic review' },
                 reviewer: admin)
    latest = review.compare
    summaries = CbbdReviewRun.listing(season.id).fetch(:runs)
    expect(summaries.first.attributes.keys).to match_array(%w[id status start_date end_date created_at])
    versions = run.comparison_summaries
    expect(versions.select_values).to eq(%i[version identity_mapping_decision_id])
    expect(versions.first.has_attribute?(:report)).to be(false)
    expect(versions.pluck(:version)).to eq([2, 1])
    queries = review_queries { get admin_cbbd_review_runs_path(season_id: season.id) }
    expect(queries.grep(/FROM "cbbd_review_runs"/).join).not_to match(/manifest|normalized_replay|\.\*/)
    expect(response.body).to include("Run #{run.id}: completed, 2025-11-01 through 2025-11-02")
    queries = review_queries { get admin_cbbd_review_run_path(run, version: applied.version) }
    navigation = queries.find { |sql| sql.include?('ORDER BY "cbbd_review_comparisons"."version" DESC') }
    expect(navigation).to include('SELECT "cbbd_review_comparisons"."version"', '"identity_mapping_decision_id"')
    expect(navigation).not_to match(/report|replay|draft|\.\*/)
    document = response.parsed_body
    links = document.css('nav').find { |node| node.text.include?('Versions:') }.css('a')
    expect(links.map(&:text)).to eq(['2', '1 (applied)'])
    expect(links.pluck('href')).to eq([admin_cbbd_review_run_path(run, version: latest.version),
                                       admin_cbbd_review_run_path(run, version: applied.version)])
    expect(response.body).to include('Comparison version 1', 'Application history', 'Synthetic review', 'Synthetic Home')
    expect(run.review_comparison(applied.version)).to have_attributes(report: applied.report, replay: applied.replay,
                                                                      draft: applied.reload.draft)
  end
end
