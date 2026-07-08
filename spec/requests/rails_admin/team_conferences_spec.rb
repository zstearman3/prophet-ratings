# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RailsAdmin team conferences', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:user, :admin) }
  let(:team) { create(:team, school: 'Admin Realignment U') }
  let(:old_conference) { create(:conference, name: 'Old Conference', slug: 'old-conference') }
  let(:new_conference) { create(:conference, name: 'New Conference', slug: 'new-conference') }
  let(:season2025) { create_season(2025) }
  let(:season2026) { create_season(2026) }
  let(:season2027) { create_season(2027) }

  before do
    sign_in admin
  end

  def create_season(year)
    create(
      :season,
      year:,
      name: "#{year - 1}-#{year.to_s.last(2)}",
      start_date: Date.new(year - 1, 11, 1),
      end_date: Date.new(year, 4, 10)
    )
  end

  def create_params(start_season: season2027)
    {
      team_conference: {
        team_id: team.id,
        conference_id: new_conference.id,
        start_season_id: start_season.id,
        end_season_id: ''
      }
    }
  end

  it 'creates a membership and closes the previous membership' do
    season2026
    previous = create(:team_conference, team:, conference: old_conference, start_season: season2025)

    post '/admin/team_conference/new_team_conference', params: create_params

    expect(response).to redirect_to('/admin/team_conference')
    expect(previous.reload.end_season).to eq(season2026)
    expect(TeamConference.find_by!(team:, start_season: season2027)).to have_attributes(
      conference: new_conference,
      end_season: nil
    )
  end

  it 'renders errors and leaves the previous membership unchanged when assignment fails' do
    previous = create(:team_conference, team:, conference: old_conference, start_season: season2025)

    post '/admin/team_conference/new_team_conference', params: create_params

    expect(response).to have_http_status(:not_acceptable)
    expect(response.body).to include('requires the preceding season to close the previous membership')
    expect(previous.reload.end_season).to be_nil
    expect(TeamConference.where(team:, start_season: season2027)).to be_empty
  end

  it 'renders useful team and conference labels on index and show pages' do
    membership = create(
      :team_conference,
      team:,
      conference: old_conference,
      start_season: season2025,
      end_season: season2026
    )

    get '/admin/team_conference'

    expect(response.body).to include('Admin Realignment U')
    expect(response.body).to include('Old Conference')
    expect(response.body).not_to include("Team ##{team.id}")

    get "/admin/team_conference/#{membership.id}"

    expect(response.body).to include('Admin Realignment U')
    expect(response.body).to include('Old Conference')
    expect(response.body).to include('2025-2026')
    expect(response.body).not_to include("Team ##{team.id}")
  end

  it 'does not expose bulk delete for team conferences' do
    create(:team_conference, team:, conference: old_conference, start_season: season2025)

    get '/admin/team_conference'

    expect(response.body).not_to include('bulk_delete')
  end
end
