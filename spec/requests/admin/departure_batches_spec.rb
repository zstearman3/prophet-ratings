# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin departure batches' do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:user, :admin) }
  let(:season) { create(:season, year: 2026) }
  let(:team) { create(:team, school: 'Sample School') }

  before do
    create(:team_season, season:, team:)
    TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: '20')
    stub_cbbd
  end

  def create_from_form
    get admin_departure_batches_path(season_id: season.id)
    form = response.parsed_body.at_css('form[action="/admin/departure_batches"][method="post"]')
    expect(form).to be_present
    post form['action'], params: { season_id: season.id, preparation: cbbd_fields }
    expect(response).to have_http_status(:redirect)
    DepartureBatch.last
  end

  it 'uses CBBD forms to create, reopen, acquire, save decisions, approve and correct' do
    sign_in admin
    batch = create_from_form
    follow_redirect!
    expect(response.body).to include('Departure batch', 'Back to offseason setup')
    preparation = response.parsed_body.at_css('input[name="preparation[expected_picks]"]')
    expect(preparation['value'].split.size).to eq(60)
    patch admin_departure_batch_path(batch), params: { preparation: cbbd_fields }
    expect(batch.reload.plan['sources'].size).to eq(5)
    allow(AcquireDepartureBatchJob).to receive(:perform_later)
    post acquire_admin_departure_batch_path(batch)
    expect(AcquireDepartureBatchJob).to have_received(:perform_later).with(kind_of(Integer))
    attempt = batch.attempt
    AcquireDepartureBatchJob.perform_now(attempt.id)
    get admin_departure_batch_path(batch)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Round 1', 'Round 2', '500 points / 2000', 'Save decisions')
    key = response.parsed_body.at_css('input[name="review[review_key]"]')['value']
    patch admin_departure_batch_path(batch), params: { review: { review_key: key, rows: cbbd_rows(team) } }
    follow_redirect!
    expect(response.body).to include('0.25', 'verified_production')
    forms = response.parsed_body.css('form')
    approval = forms.find { |form| form['action'] == publish_admin_departure_batch_path(batch) }
    expect(approval.at_css('input[name="review[confirm]"][type="checkbox"]')['checked']).to be_nil
    patch approval['action'], params: { review: { review_key: approval.at_css('input[name="review[review_key]"]')['value'], confirm: '1' } }
    expect(batch.reload.status).to eq('published')
    post correct_admin_departure_batch_path(batch), params: { reason: 'Decision correction' }
    follow_redirect!
    expect(response.body).to include('Correction of', 'approval and acknowledgement cleared')
    expect(DepartureBatch.last.predecessor_id).to eq(batch.id)
  end

  it 'serves retained JSON as private text attachments and rejects HTML fallback' do
    sign_in admin
    batch = create_from_form
    attempt = capture_cbbd(batch)
    get admin_departure_batch_path(batch)
    expect(response.parsed_body.at_css('form[enctype="multipart/form-data"]')).to be_nil
    post recover_admin_departure_batch_path(batch), params: { recovery: { source_id: 'draft' } }
    expect(response).to have_http_status(:unprocessable_content)
    get source_admin_departure_batch_path(batch, attempt_id: attempt.id, source_id: 'draft')
    expect(response.headers['Content-Disposition']).to include('attachment', '.json')
    expect(response.media_type).to eq('text/plain')
    expect(JSON.parse(response.parsed_body).size).to eq(60)
  end

  it 'returns actionable invalid input without losing saved preparation' do
    sign_in admin
    batch = create_from_form
    patch admin_departure_batch_path(batch), params: { preparation: cbbd_fields.merge('expected_picks' => '1 1') }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Duplicate expected picks')
    expect(batch.reload.plan['expected_picks'].size).to eq(60)
  end

  it 'guards every endpoint before loading private evidence' do
    requests = [[:get, admin_departure_batches_path], [:post, admin_departure_batches_path],
                [:get, admin_departure_batch_path(999)], [:patch, admin_departure_batch_path(999)],
                [:post, acquire_admin_departure_batch_path(999)], [:post, recover_admin_departure_batch_path(999)],
                [:post, correct_admin_departure_batch_path(999)], [:patch, publish_admin_departure_batch_path(999)],
                [:get, source_admin_departure_batch_path(999)]]
    requests.each do |verb, path|
      public_send(verb, path)
      expect(response).to redirect_to(new_user_session_path)
    end
    sign_in create(:user)
    requests.each do |verb, path|
      public_send(verb, path)
      expect(response).to have_http_status(:not_found)
    end
  end

  def acquisition_queries(&)
    queries = []
    subscriber = lambda do |_event, _start, _finish, _id, payload|
      queries << payload[:sql] if payload[:sql].match?(/SELECT .*FROM "?departure_acquisitions"?/)
    end
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record', &)
    queries
  end

  it 'rejects a real zero-byte multipart upload without changing retained state or publication pointers' do
    sign_in admin
    original = legacy_departure_batch(season)
    capture_departures(original)
    save_departure_rows(original, departure_rows(team))
    revision = approve_departures(original)
    correction = Departures::BatchPreparation.new(original.reload).correct('Retry saved source')
    before = [correction.attributes, correction.acquisitions.map(&:attributes), TeamOffseasonProfile.all.map(&:attributes)]
    Tempfile.create(['empty-departure', '.html']) do |empty|
      upload = Rack::Test::UploadedFile.new(empty.path, 'text/html')
      post recover_admin_departure_batch_path(correction), params: {
        recovery: { source_id: 'source-1', url: departure_fields.dig('sources', '0', 'url'), http_status: '200',
                    captured_at: '2026-10-21T10:00:00Z', observed_at: '2026-10-21T10:00:00Z',
                    source_as_of_reason: 'Unavailable', html: upload }
      }
    end
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Saved HTML must contain bytes')
    expect([correction.reload.attributes, correction.acquisitions.map(&:attributes),
            TeamOffseasonProfile.all.map(&:attributes)]).to eq(before)
    expect(TeamOffseasonProfile.pluck(:departure_revision_id)).to eq([revision.id])
  end

  it 'loads full evidence once for a sixty-pick review and omits it from history and index summaries' do
    sign_in admin
    batch = create_from_form
    2.times { capture_cbbd(batch) }
    allow(Departures::BatchPage).to receive(:table_options).and_call_original
    queries = acquisition_queries { get admin_departure_batch_path(batch) }
    expect(response.body).to include('Pick 60', 'Attempt #', '500 points / 2000')
    expect(queries.grep(/"departure_acquisitions"\.\*/).size).to eq(1)
    expect(queries.size).to eq(2)
    expect(queries.last).not_to include('evidence', 'plan')
    expect(Departures::BatchPage).to have_received(:table_options).once
  end

  it 'lists acquisition statuses without loading raw evidence rows' do
    sign_in admin
    batch = create_from_form
    2.times { capture_cbbd(batch) }
    Departures::BatchPreparation.create(season, cbbd_fields)
    listing_queries = acquisition_queries { get admin_departure_batches_path(season_id: season.id) }
    expect(response.body).to include('completed')
    expect(listing_queries.grep(/"departure_acquisitions"\.\*/)).to eq([])
    expect(listing_queries.size).to eq(1)
    expect(listing_queries.join).not_to include('evidence', 'dataset')
  end
end
