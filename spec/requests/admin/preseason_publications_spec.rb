# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin preseason publication' do
  include Devise::Test::IntegrationHelpers

  let(:season) { create(:season) }
  let(:admin) { create(:user, :admin) }
  let(:model) { RatingsConfigVersion.publish! }
  let!(:row) { create(:team_season, season:) }

  before do
    allow(PublishPreseasonJob).to receive(:perform_later).and_return(true)
    allow(PreviewPreseasonJob).to receive(:perform_later).and_return(true)
  end

  it 'restricts all review actions to administrators' do
    get admin_preseason_publications_path(season_id: season.id)
    expect(response).to redirect_to(new_user_session_path)
    sign_in create(:user)
    post select_model_admin_preseason_publications_path(season_id: season.id), params: { model_id: model.id }
    expect(response).to have_http_status(:not_found)
    expect(season.reload.selected_preseason_model_id).to be_nil
  end

  it 'persists selection across navigation without changing defaults or input approvals' do
    sign_in admin
    original = season.attributes.slice('participation_review', 'membership_proposal')
    post select_model_admin_preseason_publications_path(season_id: season.id), params: { model_id: model.id }
    follow_redirect!
    expect(response.body).to include(model.name, 'Create read-only rating preview')
    get admin_offseason_setup_path(season_id: season.id)
    expect(response.body).to include("Selected model #{model.name}", 'Preview and publish preseason ratings')
    expect(season.reload.attributes.slice('participation_review', 'membership_proposal')).to eq(original)
    expect(RatingsConfigVersion.current).to be_nil
  end

  it 'renders readable pinned preview details and retained acknowledgement after publishing' do
    sign_in admin
    PreseasonPublication.select_model(season, model)
    post admin_preseason_publications_path(season_id: season.id), params: { mode: 'initialize' }
    follow_redirect!
    expect(response.body).to include('preview_queued', 'Retry pinned preview')
    expect(response.body).not_to include('Publish reviewed preseason ratings')
    PreviewPreseasonJob.perform_now(PreseasonPublication.last.id)
    get admin_preseason_publication_path(PreseasonPublication.last, season_id: season.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Unknown', 'Legacy adjustment components', 'Captured source and revision provenance',
                                     'Largest rank movers', 'Missing returning minutes fraction', model.name, row.team.school)
    review = PreseasonPublication.last
    expect([PreseasonPrior.count, TeamRatingSnapshot.count]).to eq([0, 0])
    post publish_admin_preseason_publication_path(review, season_id: season.id),
         params: { fingerprint: review.fingerprint, acknowledge: '1' }
    PreseasonPublicationExecution.new(review).call
    get admin_preseason_publication_path(review, season_id: season.id)
    expect(response.body).to include('Published outputs', "Acknowledged by admin ##{admin.id}", 'Missing returning minutes fraction')
    table = response.parsed_body.at_css('#published-preseason-ratings')
    expect(table).to be_present
    snapshot = TeamRatingSnapshot.find(review.reload.result.fetch('snapshot_ids').first)
    expect(PreseasonPublicationPage.outputs(review).first).not_to have_attribute(:stats)
    expected = [review.result.fetch('ranks').to_h.fetch(row.team_id).to_s, row.team.school,
                format('%.2f', snapshot.rating), format('%.2f', snapshot.adj_offensive_efficiency),
                format('%.2f', snapshot.adj_defensive_efficiency), format('%.1f', snapshot.adj_pace)]
    expect(table.css('tbody tr').map { |entry| entry.css('td').map { |cell| cell.text.strip } }).to eq([expected])
    row.update!(rating: 999, adj_offensive_efficiency: 999)
    get admin_preseason_publication_path(review, season_id: season.id)
    expect(response.parsed_body.at_css('#published-preseason-ratings').css('tbody td').map { |cell| cell.text.strip }).to eq(expected)
    expect(response.body).to include('Publication completed', '1 saved team ratings')
    expect(season.reload).not_to be_current
  end

  it 'orders the proposal by proposed rank and formats the ratings for comparison' do
    stronger = create(:team_season, season:)
    create(:team_offseason_profile, team_season: row, manual_adjustment: -2)
    create(:team_offseason_profile, team_season: stronger, manual_adjustment: 2)
    sign_in admin
    PreseasonPublication.select_model(season, model)
    review = PreseasonPublication.review!(season, reviewer: admin, mode: 'initialize')
    PreviewPreseasonJob.perform_now(review.id)
    get admin_preseason_publication_path(review, season_id: season.id)
    entries = response.parsed_body.css('#proposed-preseason-ratings tbody tr')
    expect(entries.map { |entry| entry.at_css('td').text }).to eq([stronger.team.school, row.team.school])
    expect(entries.first.css('td')[1].text).to match(/→ \d+\.\d{2}\z/)
  end

  it 'returns validation guidance and prevents cross-season review access' do
    sign_in admin
    PreseasonPublication.select_model(season, model)
    review = PreseasonPublication.review!(season, reviewer: admin, mode: 'initialize')
    PreviewPreseasonJob.perform_now(review.id)
    review.reload
    post publish_admin_preseason_publication_path(review, season_id: season.id),
         params: { fingerprint: review.fingerprint, acknowledge: '0' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Explicitly acknowledge')
    other = create(:season, year: 2028)
    get admin_preseason_publication_path(review, season_id: other.id)
    expect(response).to have_http_status(:not_found)
  end

  it 'resubmits an interrupted queued publication without replacing the original gap acknowledgement' do
    sign_in admin
    PreseasonPublication.select_model(season, model)
    review = PreseasonPublication.review!(season, reviewer: admin, mode: 'initialize')
    PreviewPreseasonJob.perform_now(review.id)
    review.reload
    path = publish_admin_preseason_publication_path(review, season_id: season.id)
    post path, params: { fingerprint: review.fingerprint, acknowledge: '1' }
    acknowledgement = review.reload.acknowledgement
    post path, params: { fingerprint: review.fingerprint, acknowledge: '0' }
    expect(PublishPreseasonJob).to have_received(:perform_later).with(review.id).twice
    expect(review.reload.acknowledgement).to eq(acknowledgement)
    follow_redirect!
    expect(response.body).to include('Requeue reviewed publication')
  end

  it 'returns authenticated lightweight status without calculating or exposing evidence' do
    sign_in admin
    PreseasonPublication.select_model(season, model)
    review = PreseasonPublication.review!(season, reviewer: admin, mode: 'initialize')
    get progress_admin_preseason_publication_path(review, season_id: season.id), as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.keys).to match_array(%w[status updated_at])
    expect(response.parsed_body['status']).to eq('preview_queued')
    other = create(:season, year: 2028)
    get progress_admin_preseason_publication_path(review, season_id: other.id), as: :json
    expect(response).to have_http_status(:not_found)
  end
end
