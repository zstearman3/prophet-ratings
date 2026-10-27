# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Asynchronous offseason readiness' do
  include Devise::Test::IntegrationHelpers

  let(:season) { create(:season) }
  let(:admin) { create(:user, :admin) }

  it 'loads the readiness page without calculating the report during the request' do
    sign_in admin
    allow(OffseasonReadiness).to receive(:new).and_call_original
    get admin_offseason_readiness_reviews_path(season_id: season.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Preparing readiness report')
    expect(OffseasonReadiness).not_to have_received(:new)
  end

  it 'restricts operation creation and progress to admins and the correct season' do
    operation = OffseasonReadinessOperation.create!(season:, actor: admin, action: 'report')
    path = progress_admin_offseason_readiness_operation_path(operation, season_id: season.id)
    get path
    expect(response).to redirect_to(new_user_session_path)
    sign_in create(:user)
    get path
    expect(response).to have_http_status(:not_found)
    sign_in admin
    other = create(:season, year: 2030)
    get progress_admin_offseason_readiness_operation_path(operation, season_id: other.id)
    expect(response).to have_http_status(:not_found)
  end

  it 'coalesces repeated report requests and permits recovery of a stuck running operation' do
    sign_in admin
    allow(ReadinessOperationJob).to receive(:perform_later).and_return(true)
    path = admin_offseason_readiness_operations_path(season_id: season.id)
    post path
    operation = OffseasonReadinessOperation.last
    post path
    expect(OffseasonReadinessOperation.count).to eq(1)
    expect(ReadinessOperationJob).to have_received(:perform_later).once
    operation.update!(status: 'running')
    post retry_admin_offseason_readiness_operation_path(operation, season_id: season.id)
    expect(ReadinessOperationJob).to have_received(:perform_later).twice
    expect(operation.reload.status).to eq('running')
  end
end
