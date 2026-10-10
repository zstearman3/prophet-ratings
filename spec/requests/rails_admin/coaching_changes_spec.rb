# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RailsAdmin coaching review', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:team) { create(:team, school: 'Synthetic Review U') }

  it 'requires authentication and existing admin permission' do
    get '/admin/coaching_change'
    expect(response).to redirect_to('/users/sign_in')
    sign_in create(:user)
    get '/admin/coaching_change'
    expect(response).to redirect_to('/')
  end

  context 'with an admin' do
    before { sign_in create(:user, :admin) }

    it 'renders create forms with existing team selectors and independent year fields' do
      get '/admin/coaching_change/new'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('coaching_change[effective_year]', 'coaching_change[reconfirm]',
                                       'coaching_change[previous_season_d1]')
      %i[team previous_team].each do |name|
        field = RailsAdmin.config(CoachingChange).edit.fields.find { |entry| entry.name == name }
        expect(field.inline_add).to be(false)
        expect(field.inline_edit).to be(false)
      end
    end

    it 'creates and reviews coaching facts without writing model outputs or legacy profiles' do
      post '/admin/coaching_change/new', params: {
        coaching_change: { team_id: team.id, effective_year: 2027, coach_name: 'Synthetic Coach', status: 'pending' }
      }
      expect(response).to have_http_status(:found)
      change = CoachingChange.last
      put "/admin/coaching_change/#{change.id}/edit", params: { coaching_change: { status: 'confirmed' } }
      expect(response).to have_http_status(:found)
      expect(change.reload).to be_confirmed
      expect([Season.count, TeamSeason.count, TeamOffseasonProfile.count, TeamRatingSnapshot.count,
              Prediction.count, PreseasonPrior.count]).to eq([0, 0, 0, 0, 0, 0])
    end

    it 'renders list, filters and show with readable coaching facts' do
      change = CoachingChange.create!(team: team, effective_year: 2027, coach_name: 'Synthetic Coach', status: 'confirmed')
      get '/admin/coaching_change', params: { f: { status: { '0' => { v: 'confirmed', o: 'is' } } } }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Synthetic Review U', 'Synthetic Coach', '2027')
      get "/admin/coaching_change/#{change.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Synthetic Coach')
    end

    it 'shows actionable correction errors and accepts explicit reconfirmation' do
      change = CoachingChange.create!(team: team, effective_year: 2027, coach_name: 'Synthetic Coach', status: 'confirmed')
      put "/admin/coaching_change/#{change.id}/edit", params: { coaching_change: { coach_name: 'Corrected Coach' } }
      expect(response).to have_http_status(:not_acceptable)
      expect(response.body).to include('explicitly reconfirm')
      put "/admin/coaching_change/#{change.id}/edit", params: { coaching_change: { coach_name: 'Corrected Coach', reconfirm: '1' } }
      expect(response).to have_http_status(:found)
      expect(change.reload.coach_name).to eq('Corrected Coach')
    end

    it 'marks empty years ready and rejects readiness with pending candidates' do
      post '/admin/coaching_review/new', params: { coaching_review: { year: 2027, ready: '1' } }
      expect(response).to have_http_status(:found)
      review = CoachingReview.find_by!(year: 2027)
      CoachingChange.create!(effective_year: 2027)
      put "/admin/coaching_review/#{review.id}/edit", params: { coaching_review: { ready: '1' } }
      expect(response).to have_http_status(:not_acceptable)
      expect(response.body).to include('requires confirming or rejecting every pending')
    end
  end
end
