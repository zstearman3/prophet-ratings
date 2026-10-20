# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RailsAdmin ratings config versions', type: :request do
  include Devise::Test::IntegrationHelpers

  before { sign_in create(:user, :admin) }

  def submitted_config(payload)
    JSON.generate(payload.deep_stringify_keys)
  end

  def create_path
    get '/admin/ratings_config_version/new'
    form = response.parsed_body.css('form').find { |node| node['method']&.casecmp('post')&.zero? }
    form['action']
  end

  it 'shows field errors for malformed JSON config without raising or persisting' do
    payload = RatingsConfigVersion.authored_config.merge(home_cort_advantage: 20)
    active = create(:ratings_config_version, name: 'admin-active', current: true)

    post create_path, params: {
      ratings_config_version: { name: payload[:bundle_name], current: '0', config: submitted_config(payload) }
    }

    expect(response).not_to have_http_status(:internal_server_error)
    expect(response.body).to include('home_cort_advantage')
    expect(RatingsConfigVersion.exists?(name: payload[:bundle_name])).to be(false)
    expect(RatingsConfigVersion.current).to eq(active)
  end

  it 'persists a valid JSON config without activating it' do
    payload = RatingsConfigVersion.authored_config.merge(bundle_name: 'admin-valid')
    active = create(:ratings_config_version, name: 'admin-active', current: true)

    post create_path, params: {
      ratings_config_version: { name: 'admin-valid', current: '0', config: submitted_config(payload) }
    }

    expect(response).to be_redirect
    expect(RatingsConfigVersion.find_by!(name: 'admin-valid').current).to be(false)
    expect(RatingsConfigVersion.current).to eq(active)
  end

  it 'rejects a JSON config whose bundle name differs from the record name' do
    payload = RatingsConfigVersion.authored_config.merge(bundle_name: 'canonical-admin-name')
    active = create(:ratings_config_version, name: 'admin-active', current: true)

    post create_path, params: {
      ratings_config_version: { name: 'alias-admin-name', current: '0', config: submitted_config(payload) }
    }

    expect(response).not_to have_http_status(:internal_server_error)
    expect(response.body).to include('must match config.bundle_name')
    expect(RatingsConfigVersion.exists?(name: 'alias-admin-name')).to be(false)
    expect(RatingsConfigVersion.current).to eq(active)
  end

  it 'renders shape errors for a malformed required nested object' do
    payload = RatingsConfigVersion.authored_config.merge(weighting: 'bad')

    post create_path, params: {
      ratings_config_version: { name: payload[:bundle_name], current: '0', config: submitted_config(payload) }
    }

    expect(response).not_to have_http_status(:internal_server_error)
    expect(response.body).to include('config.weighting')
    expect(RatingsConfigVersion.exists?(name: payload[:bundle_name])).to be(false)
  end

  it 'renders root shape errors for scalar, array, and null JSON payloads' do
    [nil, [], 'bad'].each_with_index do |root, index|
      name = "admin-root-#{index}"
      post create_path, params: {
        ratings_config_version: { name:, current: '0', config: JSON.generate(root) }
      }

      expect(response).not_to have_http_status(:internal_server_error)
      expect(response.body).to match(/config.*object/i)
      expect(RatingsConfigVersion.exists?(name:)).to be(false)
    end
  end
end
