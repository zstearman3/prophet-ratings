# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Games' do
  describe 'GET /index' do
    it 'returns http success' do
      get '/games/index'
      expect(response).to have_http_status(:success)
    end
  end
end
