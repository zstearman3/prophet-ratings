# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GoodJob dashboard access', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:job) do
    GoodJob::Job.create!(
      active_job_id: SecureRandom.uuid,
      job_class: 'ApplicationJob',
      serialized_params: {},
      finished_at: Time.current
    )
  end

  shared_examples 'denied dashboard access' do |status|
    ['/good_job', '/good_job/jobs', '/good_job/jobs/metrics/job_status'].each do |path|
      it "denies access to #{path}" do
        get path

        expect(response).to have_http_status(status)
      end
    end

    it 'does not allow deleting a job' do
      delete "/good_job/jobs/#{job.id}"

      expect(response).to have_http_status(status)
      expect(GoodJob::Job.exists?(job.id)).to be true
    end
  end

  context 'when signed out' do
    it_behaves_like 'denied dashboard access', :found

    it 'redirects to the application sign-in page' do
      get '/good_job/jobs'

      expect(response).to redirect_to('/users/sign_in')
    end
  end

  context 'when signed in as a non-admin' do
    before { sign_in create(:user) }

    it_behaves_like 'denied dashboard access', :not_found
  end

  context 'when signed in as an admin' do
    before { sign_in create(:user, :admin) }

    it 'opens the dashboard' do
      get '/good_job'

      expect(response).to redirect_to('/good_job/jobs?locale=en')
      follow_redirect!
      expect(response).to have_http_status(:ok)
    end

    it 'allows deleting a finished job' do
      delete "/good_job/jobs/#{job.id}"

      expect(response).to have_http_status(:see_other)
      expect(GoodJob::Job.exists?(job.id)).to be false
    end
  end

  it 'keeps the public health check accessible' do
    get '/up'

    expect(response).to have_http_status(:ok)
  end
end
