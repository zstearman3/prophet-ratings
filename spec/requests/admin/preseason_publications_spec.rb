# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin preseason publication' do
  include Devise::Test::IntegrationHelpers

  let(:season) { create(:season) }
  let(:admin) { create(:user, :admin) }
  let(:model) { RatingsConfigVersion.publish! }
  let!(:row) { create(:team_season, season:) }

  before { allow(PublishPreseasonJob).to receive(:perform_later).and_return(true) }

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
    expect(season.reload).not_to be_current
  end

  it 'returns validation guidance and prevents cross-season review access' do
    sign_in admin
    PreseasonPublication.select_model(season, model)
    review = PreseasonPublication.review!(season, reviewer: admin, mode: 'initialize')
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
    path = publish_admin_preseason_publication_path(review, season_id: season.id)
    post path, params: { fingerprint: review.fingerprint, acknowledge: '1' }
    acknowledgement = review.reload.acknowledgement
    post path, params: { fingerprint: review.fingerprint, acknowledge: '0' }
    expect(PublishPreseasonJob).to have_received(:perform_later).with(review.id).twice
    expect(review.reload.acknowledgement).to eq(acknowledgement)
    follow_redirect!
    expect(response.body).to include('Requeue reviewed publication')
  end
end
