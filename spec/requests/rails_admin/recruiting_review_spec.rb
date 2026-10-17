# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin recruiting dataset review', type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:season) { create(:season, year: 2027) }
  let(:team) { create(:team, school: 'Test College') }
  let(:path) { '/admin/recruiting_batches' }
  let(:document) { JSON.parse(Rails.root.join('spec/fixtures/recruiting/partial.json').read) }
  let(:batch) do
    bytes = JSON.generate(document)
    dataset = Recruiting::Dataset.new(bytes, 'retained recruiting fixture')
    RecruitingBatch.create!(season:, source_year: 2026, status: 'ready', source_status: 'ok', extract_bytes: bytes,
                            snapshot_bytes: 'retained recruiting fixture',
                            dataset_revision: dataset.manifest.fetch('dataset_revision')).tap do |record|
      Recruiting::Preview.new(dataset, season).call.fetch('rows').each do |row|
        record.entries.create!(RecruitingEntry.source_attributes(row))
      end
    end
  end
  let(:batch_path) { "#{path}/#{batch.id}" }
  let(:admin) { create(:user, :admin) }

  before do
    team
    sign_in admin
  end

  def review_values
    get batch_path
    form = response.parsed_body.at_css('#recruiting-review-form')
    { review_key: form.at_css('input[name="review[review_key]"]')['value'], confirm: '1',
      rows: batch.entries.reload.to_h { |entry| [entry.id.to_s, { team_id: entry.team_id.to_s }] } }
  end

  it 'links the season admin to its recruiting batches and exposes a human-readable review table' do
    get "/admin/season/#{season.id}"
    expect(response.body).to include('Review recruiting')
    get "/admin/season/#{season.id}/review_recruiting"
    expect(response).to redirect_to("#{path}?season_id=#{season.id}")
    get path, params: { season_id: season.id }
    expect(response.body).to include('Fetch recruiting data', '2026', '2027')
    get batch_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Test College', '70.123456789123456789', 'Approve and publish recruiting inputs', 'Class points')
    expect(response.body).not_to include('REVIEW_PATH', 'INPUT_HASH', 'base64')
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'queues the automated fetch in a new database batch' do
    allow(AcquireRecruitingBatchJob).to receive(:perform_later)
    post path, params: { season_id: season.id }
    record = RecruitingBatch.last
    expect(record).to have_attributes(season_id: season.id, source_year: 2026, status: 'queued')
    expect(AcquireRecruitingBatchJob).to have_received(:perform_later).with(record.id)
    expect(response).to redirect_to("#{path}/#{record.id}")
    follow_redirect!
    expect(response.body).to include('background worker', 'Refresh status')
  end

  it 'renders a failed report once without retrying it inside the error handler' do
    batch
    review = instance_double(Recruiting::BatchReview)
    allow(Recruiting::BatchReview).to receive(:new).and_return(review)
    allow(review).to receive(:report).and_raise(ActiveRecord::StatementInvalid, 'Report unavailable')

    get batch_path

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Report unavailable')
    expect(review).to have_received(:report).once
  end

  it 'saves a mapping override without publishing, then approves from the rendered form button' do
    alternative = create(:team)
    values = review_values
    values[:rows][batch.entries.sole.id.to_s][:team_id] = alternative.id.to_s
    patch batch_path, params: { review: values }
    expect(response).to redirect_to(batch_path)
    expect(batch.entries.reload.sole.team_id).to eq(alternative.id)
    expect(OffseasonInputRevision.count).to eq(0)
    values = review_values
    button = response.parsed_body.css('#recruiting-review-form button').find { |entry| entry['formaction'] }
    patch button['formaction'], params: { review: values }
    expect(response).to redirect_to(batch_path)
    follow_redirect!
    expect(response.body).to include('Approved by', admin.email)
    expect(batch.reload.revision.team_input(alternative.id)).to include('class_points' => '70.123456789123456789')
  end

  it 'approves pending mapping edits in the same submission without an extra save step' do
    alternative = create(:team)
    values = review_values
    values[:rows][batch.entries.sole.id.to_s][:team_id] = alternative.id.to_s
    patch "#{batch_path}/publish", params: { review: values }
    expect(response).to redirect_to(batch_path)
    expect(batch.reload.revision.team_input(alternative.id)).to include('status' => 'verified_points')
  end

  it 'shows unresolved errors and preserves submitted choices instead of publishing partial accidental mappings' do
    values = review_values
    values[:rows][batch.entries.sole.id.to_s][:team_id] = ''
    patch "#{batch_path}/publish", params: { review: values }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Map or explicitly exclude')
    expect(OffseasonInputRevision.count).to eq(0)
    expect(batch.reload.status).to eq('ready')
  end

  it 'rejects a stale preview and does not accept numeric mass assignment' do
    values = review_values
    batch.entries.sole.update!(excluded: true)
    patch "#{batch_path}/publish", params: { review: values }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('review changed')
    values = review_values
    values[:rows][batch.entries.sole.id.to_s].merge!(class_points: '999', excluded: '1')
    patch batch_path, params: { review: values }
    expect(response).to redirect_to(batch_path)
    expect(batch.entries.reload.sole.class_points.to_s('F')).to eq('70.123456789123456789')
    expect(batch.entries.reload.sole).not_to be_excluded
  end

  it 'renders 50 rows per page and still blocks unresolved rows on other pages' do
    first = document.fetch('rows').first
    document['rows'] = Array.new(51) do |number|
      first.merge('team_label' => "Source school #{number}", 'provider_team_id' => "source-#{number}", 'rank' => number + 1)
    end
    get batch_path
    expect(response.parsed_body.css('#recruiting-review-form tbody tr').size).to eq(50)
    expect(response.body).to include('Next page', 'Page 1 of 2')
    get batch_path, params: { page: 2 }
    expect(response.parsed_body.css('#recruiting-review-form tbody tr').size).to eq(1)
    entry = batch.entries.order(:row_number).last
    key = response.parsed_body.at_css('input[name="review[review_key]"]')['value']
    patch "#{batch_path}/publish", params: { review: {
      review_key: key, confirm: '1', rows: { entry.id.to_s => { team_id: team.id.to_s } }
    } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'protects every read, fetch, mapping and approval action with the admin login' do
    record_path = batch_path
    sign_out :user
    get path
    expect(response).to redirect_to('/users/sign_in')
    post path, params: { season_id: season.id }
    expect(response).to redirect_to('/users/sign_in')
    get record_path
    expect(response).to redirect_to('/users/sign_in')
    patch record_path, params: { review: {} }
    expect(response).to redirect_to('/users/sign_in')
    patch "#{record_path}/publish", params: { review: {} }
    expect(response).to redirect_to('/users/sign_in')
    sign_in create(:user)
    get record_path
    expect(response).to redirect_to('/')
    post path, params: { season_id: season.id }
    expect(response).to redirect_to('/')
    patch record_path, params: { review: {} }
    expect(response).to redirect_to('/')
    patch "#{record_path}/publish", params: { review: {} }
    expect(response).to redirect_to('/')
    expect(OffseasonInputRevision.count).to eq(0)
  end
end
