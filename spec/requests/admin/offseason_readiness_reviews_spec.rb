# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin offseason readiness reviews' do
  include Devise::Test::IntegrationHelpers
  include ReadinessFixture

  let(:season) { create(:season) }
  let(:model) { RatingsConfigVersion.publish! }
  let(:admin) { create(:user, :admin) }
  let(:row) { create(:team_season, season:) }

  before { allow(PublishPreseasonJob).to receive(:perform_later).and_return(true) }

  it 'restricts reading, recording and activation to administrators' do
    get admin_offseason_readiness_reviews_path(season_id: season.id)
    expect(response).to redirect_to(new_user_session_path)
    sign_in create(:user)
    get admin_offseason_readiness_reviews_path(season_id: season.id)
    expect(response).to have_http_status(:not_found)
    post admin_offseason_readiness_reviews_path(season_id: season.id)
    expect(response).to have_http_status(:not_found)
    post activate_season_admin_offseason_readiness_review_path(1, season_id: season.id)
    expect(response).to have_http_status(:not_found)
    post activate_model_admin_offseason_readiness_review_path(1, season_id: season.id)
    expect(response).to have_http_status(:not_found)
  end

  it 'shows read-only evidence and season-scoped repair links without saving or enqueueing' do
    sign_in admin
    path = admin_offseason_readiness_reviews_path(season_id: season.id)
    expect { get path }.not_to change(OffseasonReadinessReview, :count)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('No usable schedule', 'Save readiness review', 'does not certify prediction accuracy')
    expect(response.body).to include(admin_preseason_publications_path(season_id: season.id),
                                     admin_schedule_refresh_runs_path(season_id: season.id),
                                     admin_offseason_setup_path(season_id: season.id))
    expect(PublishPreseasonJob).not_to have_received(:perform_later)
  end

  it 'retains review decisions, activates separately and revisits original evidence with actual state' do
    sign_in admin
    publish_readiness_fixture(season, model, row, admin)
    report = OffseasonReadiness.new(season).call
    post admin_offseason_readiness_reviews_path(season_id: season.id),
         params: { fingerprint: report['fingerprint'], acknowledge: '1', deferrals: { schedule: 'Await schedule publication' } }
    follow_redirect!
    expect(response.body).to include('Retained readiness review', 'Await schedule publication', 'Make model default',
                                     'jobs omitting season ID')
    review = OffseasonReadinessReview.last
    post activate_season_admin_offseason_readiness_review_path(review, season_id: season.id), params: { model_id: 999_999 }
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(season.reload).to be_current
    expect(response.body).to include('Evidence changed', "Actual current season ##{season.id}", 'succeeded')
    expect(RatingsConfigVersion.current).to be_nil
    post activate_model_admin_offseason_readiness_review_path(review, season_id: season.id)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('stale', 'Await schedule publication')
    expect(review.reload.results.keys).to eq(['season'])
  end

  it 'rejects stale form evidence and cross-season review reads/actions' do
    sign_in admin
    publish_readiness_fixture(season, model, row, admin)
    review = save_readiness_review(season, admin)
    season.update!(end_date: season.end_date + 1)
    post admin_offseason_readiness_reviews_path(season_id: season.id), params: { fingerprint: review.fingerprint, acknowledge: '1' }
    expect(response).to have_http_status(:unprocessable_content)
    other = create(:season, year: 2030)
    get admin_offseason_readiness_review_path(review, season_id: other.id)
    expect(response).to have_http_status(:not_found)
    post activate_model_admin_offseason_readiness_review_path(review, season_id: other.id)
    expect(response).to have_http_status(:not_found)
    expect([RatingsConfigVersion.current, Season.current]).to eq([nil, nil])
  end

  it 'rejects forged or required deferral keys at the HTTP boundary without creating a review' do
    sign_in admin
    publish_readiness_fixture(season, model, row, admin)
    report = OffseasonReadiness.new(season).call
    %w[forged publication].each do |key|
      expect do
        post admin_offseason_readiness_reviews_path(season_id: season.id),
             params: { fingerprint: report['fingerprint'], acknowledge: '1', deferrals: { key => 'Skip' } }
      end.not_to change(OffseasonReadinessReview, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('optional open checks')
    end
  end

  it 'keeps every Model analysis entrypoint on the fresh selected season and candidate model' do
    sign_in admin
    publish_readiness_fixture(season, model, row, admin)
    create(:ratings_config_version).activate
    get admin_offseason_readiness_reviews_path(season_id: season.id)
    links = response.parsed_body.xpath('//a[text()="Model analysis"]').pluck('href')
    expect(links.size).to eq(2)
    expect(links).to all(eq(admin_prediction_evaluation_path(season_id: season.id, model_id: model.id)))
  end

  it 'retains historical diagnostic model links separately from the fresh selected model and roundtrips the selection' do
    sign_in admin
    publish_readiness_fixture(season, model, row, admin)
    review = save_readiness_review(season, admin)
    other = create(:ratings_config_version)
    other.activate
    PreseasonPublication.select_model(season, other)
    get admin_offseason_readiness_review_path(review, season_id: season.id)
    document = response.parsed_body
    retained = document.css('section').find { |section| section.at_css('h3')&.text&.include?('Stored prediction coverage') }
    href = retained.at_xpath('.//a[text()="Review next action"]')['href']
    expect(href).to eq(admin_prediction_evaluation_path(season_id: season.id, model_id: model.id))
    get href
    expect(response.parsed_body.at_css('select#model_id option[selected]')['value']).to eq(model.id.to_s)
    dashboard = response.parsed_body.at_xpath('//a[text()="Return to season dashboard"]')['href']
    get dashboard
    get response.parsed_body.at_xpath('//a[text()="Review readiness and explicit activation"]')['href']
    expect(response.body).to include(admin_prediction_evaluation_path(season_id: season.id, model_id: other.id).gsub('&', '&amp;'))
    expect(season.reload.selected_preseason_model).to eq(other)
  end
end
