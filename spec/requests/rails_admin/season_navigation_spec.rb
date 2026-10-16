# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RailsAdmin season navigation', type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:season) { create(:season, year: 2027, name: '2026–27') }
  let!(:version) { create(:ratings_config_version) }

  before { sign_in create(:user, :admin) }

  def association_queries(&)
    queries = []
    collect = lambda do |event|
      sql = event.payload.fetch(:sql)
      queries << sql if sql.match?(/\bFROM "(?:game_sync_dates|games|team_seasons|predictions|team_rating_snapshots|bet_recommendations)"/)
    end
    ActiveSupport::Notifications.subscribed(collect, 'sql.active_record', &)
    queries
  end

  it 'lists seasons without loading their entire game and rating history' do
    queries = association_queries { get '/admin/season' }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('2026–27')
    expect(queries).to be_empty
  end

  it 'shows season details and the membership review link without loading history' do
    queries = association_queries { get "/admin/season/#{season.id}" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('2026–27', 'Review memberships')
    expect(queries).to be_empty
  end

  it 'edits season fields without building selectors for historical associations' do
    queries = association_queries { get "/admin/season/#{season.id}/edit" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('season[start_date]')
    expect(queries).to be_empty
  end

  it 'lists model versions without loading all their predictions and snapshots' do
    queries = association_queries { get '/admin/ratings_config_version' }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(version.name)
    expect(queries).to be_empty
  end

  it 'shows a model version without loading all its predictions and snapshots' do
    queries = association_queries { get "/admin/ratings_config_version/#{version.id}" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(version.name)
    expect(queries).to be_empty
  end

  it 'does not build historical association selectors when editing a model version' do
    queries = association_queries { get "/admin/ratings_config_version/#{version.id}/edit" }
    expect(response).to have_http_status(:ok)
    expect(queries).to be_empty
  end
end
