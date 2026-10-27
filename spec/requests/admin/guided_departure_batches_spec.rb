# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Guided admin departure review' do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:user, :admin) }
  let(:season) { create(:season, year: 2026) }
  let(:team) { create(:team, school: 'Local School') }
  let(:batch) { Departures::CapturePreparation.create(season, {}) }
  let(:team_points) { 100 }

  before do
    allow(PrepareDepartureValidationJob).to receive(:perform_later)
    allow(PublishDepartureValidationJob).to receive(:perform_later)
    create(:team_season, season:, team:)
    create(:team_season, season: create(:season, year: 2025), team:)
    TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: '20')
    sign_in admin
    stub_cbbd
  end

  def cbbd_picks
    [super.first]
  end

  def cbbd_players(scope)
    return [] if scope == 'postseason'

    [super.first.merge('points' => 100)]
  end

  def cbbd_teams(scope)
    return [] if scope == 'postseason'

    [super.first.merge('teamStats' => { 'points' => { 'total' => team_points } })]
  end

  def capture
    AcquireDepartureBatchJob.perform_now(batch.attempt.id)
    PrepareDepartureValidationJob.perform_now(DepartureValidation.where(departure_batch_id: batch.id).order(:id).last.id)
    batch.reload.attempt
  end

  def coverage_fields
    { review_key: DepartureValidation.where(departure_batch_id: batch.id).maximum(:id).to_s, expected_picks: '1',
      confirm_picks: '1', picks_evidence: 'Independent final draft reference', confirm_scope: '1',
      scope_evidence: 'Reviewed completed college season', absent_postseason_team_ids: ['20'] }
  end

  it 'shows derived years and collapsed limits without writing, fetching or premature evidence fields' do
    expect { get admin_departure_batches_path(season_id: season.id) }.not_to change(DepartureBatch, :count)
    expect(response.body).to include('2025 NBA draft', 'college season ending 2025', 'Fetch draft and college stats')
    expect(response.parsed_body.at_css('details input[name="capture[max_requests]"]')).to be_present
    expect(response.parsed_body.at_css('input[name="preparation[expected_picks]"]')).to be_nil
    expect(Ingestion::Cbbd::HttpTransport).not_to have_received(:call)
  end

  it 'creates and queues once from the visible form and shows a clear waiting state on read-only refresh' do
    allow(AcquireDepartureBatchJob).to receive(:perform_later)
    post admin_departure_batches_path, params: { season_id: season.id, capture: { max_requests: '15', retries: '2' } }
    created = DepartureBatch.last
    expect(created.plan).to include('schema' => 'draft-departures-capture-v1', 'draft_year' => 2025)
    expect(created.acquisitions.count).to eq(1)
    expect(AcquireDepartureBatchJob).to have_received(:perform_later).with(created.attempt.id).once
    expect { follow_redirect! }.not_to change(DepartureAcquisition, :count)
    expect(response.body).to include('Fetch queued', 'Refresh status')
    expect(response.body).not_to include('Acquire retained sources', 'Saved draft report')
    expect(Ingestion::Cbbd::HttpTransport).not_to have_received(:call)
  end

  it 'preserves invalid capture limits and rejects incorrect derived years without creating a batch' do
    post admin_departure_batches_path, params: { season_id: season.id, capture: { max_requests: '101', retries: '2' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.at_css('input[name="capture[max_requests]"]')['value']).to eq('101')
    post admin_departure_batches_path, params: { season_id: season.id, capture: { target_year: '2040' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(DepartureBatch.count).to eq(0)
  end

  it 'shows captured players and colleges with source details collapsed and no coverage certification' do
    capture
    get admin_departure_batch_path(batch)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Confirm draft results and college teams', 'Synthetic 1', 'Local School',
                                     'Publish departure inputs')
    expect(response.parsed_body.css('input[name^="coverage["]')).to be_empty
    expect(response.parsed_body.at_css('input[name="draft_review[confirm]"][type="checkbox"]')['checked']).to be_nil
    expect(response.parsed_body.at_css('details[data-source-details]')).to be_present
    expect(response.body).not_to include('Accounting category', 'Saved draft report')
    expect(Ingestion::Cbbd::HttpTransport).to have_received(:call).exactly(5).times
  end

  it 'saves coverage offline into a successor with authenticated provenance before player review' do
    first = capture
    original = first.attributes.deep_dup
    patch coverage_admin_departure_batch_path(batch), params: { coverage: coverage_fields.merge(reviewed_by: 'forged') }
    expect(response).to redirect_to(admin_departure_batch_path(batch))
    latest = batch.reload.attempt
    expect(latest.predecessor_id).to eq(first.id)
    expect(latest.plan.dig('coverage_review', 'reviewed_by')).to eq(admin.email)
    expect(first.reload.attributes).to eq(original)
    PrepareDepartureValidationJob.perform_now(DepartureValidation.where(departure_batch_id: batch.id).maximum(:id))
    follow_redirect!
    expect(response.body).to include('Confirm draft results and college teams', 'Publish departure inputs')
    expect(Ingestion::Cbbd::HttpTransport).to have_received(:call).exactly(5).times
  end

  it 'preserves invalid coverage fields and existing evidence without certifying observed picks' do
    first = capture
    submitted = coverage_fields.merge(expected_picks: '1 59', confirm_picks: '0', picks_evidence: 'My independent source')
    patch coverage_admin_departure_batch_path(batch), params: { coverage: submitted }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Confirm picks against independent final draft results')
    expect(response.parsed_body.at_css('input[name="coverage[expected_picks]"]')['value']).to eq('1 59')
    expect(response.parsed_body.at_css('input[name="coverage[picks_evidence]"]')['value']).to eq('My independent source')
    expect(batch.reload.attempt.id).to eq(first.id)
  end

  it 'preserves a deliberately cleared proposed pick list on validation retry' do
    capture
    patch coverage_admin_departure_batch_path(batch), params: { coverage: coverage_fields.merge(expected_picks: '') }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.at_css('input[name="coverage[expected_picks]"]')['value']).to eq('')
    expect(batch.acquisitions.count).to eq(1)
  end

  it 'rejects stale review and direct publication before coverage is saved' do
    capture
    stale = coverage_fields
    patch publish_admin_departure_batch_path(batch), params: { review: { confirm: '1' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(batch.reload.status).to eq('draft')
    patch coverage_admin_departure_batch_path(batch), params: { coverage: coverage_fields }
    patch coverage_admin_departure_batch_path(batch), params: { coverage: stale }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Departure coverage changed')
    expect(batch.acquisitions.count).to eq(2)
  end

  it 'shows failed and running capture next actions without a misleading draft-report failure' do
    attempt = batch.attempt
    attempt.update!(status: 'failed', failure: 'Missing worker credentials', finished_at: Time.current)
    get admin_departure_batch_path(batch)
    expect(response.body).to include('Fetch failed', 'Missing worker credentials', 'Fetch sources again')
    expect(response.body).not_to include('Saved draft report', 'Acquire retained sources')
    batch.acquisitions.create!(plan: batch.plan, status: 'running', started_at: Time.current, predecessor: attempt)
    get admin_departure_batch_path(batch)
    expect(response.body).to include('Fetch in progress', 'Close interrupted attempt and retry')
  end

  context 'when full-roster player points differ from the independent team total' do
    let(:team_points) { 102 }

    it 'shows the discrepancy as a warning and saves coverage from the same capture' do
      first = capture
      get admin_departure_batch_path(batch)
      expect(response).to have_http_status(:ok)
      warning = response.parsed_body.at_css('[data-points-reconciliation]')
      expect(warning).to be_present
      expect(warning.text).to include('Sample School', 'Regular season', '100', '102', '-2')
      expect(response.parsed_body.at_css('input[name="draft_review[confirm]"]')).to be_present
      expect(response.body).not_to include('These sources need attention before coverage can be saved')
      patch coverage_admin_departure_batch_path(batch), params: { coverage: coverage_fields }
      expect(response).to redirect_to(admin_departure_batch_path(batch))
      latest = batch.reload.attempt
      expect(latest.predecessor_id).to eq(first.id)
      expect(latest.evidence).to eq(first.evidence)
      facts = Departures::RetainedEvidence.new(latest).dataset
      expect(facts.fetch('production').first.fetch('team_points')).to eq(102)
      PrepareDepartureValidationJob.perform_now(DepartureValidation.where(departure_batch_id: batch.id).maximum(:id))
      follow_redirect!
      expect(response.parsed_body.at_css('[data-points-reconciliation]')).to be_present
      expect(Ingestion::Cbbd::HttpTransport).to have_received(:call).exactly(5).times
    end
  end

  it 'protects coverage review with the same admin authorization as source downloads' do
    sign_out admin
    patch coverage_admin_departure_batch_path(999), params: { coverage: {} }
    expect(response).to redirect_to(new_user_session_path)
    sign_in create(:user)
    patch coverage_admin_departure_batch_path(999), params: { coverage: {} }
    expect(response).to have_http_status(:not_found)
  end
end
