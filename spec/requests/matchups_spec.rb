require 'rails_helper'

RSpec.describe "Matchups", type: :request do
  describe "GET /new" do
    it "returns http success" do
      get "/matchups/new"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /submit" do
    it "returns http success" do
      get "/matchups/submit"
      expect(response).to have_http_status(:success)
    end
  end

end
