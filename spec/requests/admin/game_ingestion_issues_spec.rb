# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Private game ingestion review', type: :request do
  include Devise::Test::IntegrationHelpers

  include_context 'with scoring review evidence'

  let(:private_details) { /game.ingestion.issues|Scoring discrepancy|Acknowledged by admin|Approved by admin|Resolve issue/i }

  let(:issue) do
    Ingestion::Cbbd::ImportObservation.new(row, season).call
    GameIngestionIssue.sole
  end

  it 'lets admins see the discrepancy and acknowledge without typing a reason' do
    sign_in admin
    get "/admin/game_ingestion_issues/#{issue.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Scoring discrepancy', '65', '63')
    patch "/admin/game_ingestion_issues/#{issue.id}", params: { resolution: { action: 'acknowledge',
                                                                              fingerprint: issue.comparison_fingerprint } }
    expect(response).to have_http_status(:redirect)
    expect(issue.reload.decisions.sole.message).to eq('Acknowledged by admin')
  end

  it 'places each betting admin-review link inside its matchup cell' do
    game = issue.game
    sign_in admin
    get betting_games_path(date: game.schedule_date)
    expect(response).to have_http_status(:ok)
    matchup = response.parsed_body.at_css('tbody tr td')
    expect(matchup.text).to include('Synthetic Away @ Synthetic Home', 'Admin review')
    expect(response.parsed_body.css('tbody > span')).to be_empty
  end

  it 'links to the issue queue without excluding source corrections on another date' do
    game = issue.game
    payload = issue.latest_observation.normalized_payload.deep_dup.merge('schedule_date' => (date + 1.day).iso8601)
    source = GameObservation.create!(provider: 'cbbd', external_game_id: '1', outcome: 'conflict', normalized_payload: payload)
    issue.refresh_source(source, game)
    sign_in admin
    get game_path(game)
    link = response.parsed_body.at_xpath('//a[text()="Admin review"]')
    expect(link).not_to be_nil
    get link['href']
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.at_css("a[href='/admin/game_ingestion_issues/#{issue.id}']")).not_to be_nil
  end

  it 'keeps all review endpoints unavailable to signed-in nonadmins' do
    sign_in create(:user)
    [[:get, '/admin/game_ingestion_issues'], [:get, "/admin/game_ingestion_issues/#{issue.id}"],
     [:patch, "/admin/game_ingestion_issues/#{issue.id}"], [:post, "/admin/game_ingestion_issues/#{issue.id}/retry"]].each do |method, path|
      public_send(method, path)
      expect(response).to have_http_status(:not_found)
    end
    expect(issue.decisions.count).to eq(0)
    expect(CbbdReviewRun.count).to eq(0)
  end

  it 'shows ordinary results with no review details to guests and nonadmins before and after acknowledgement' do
    game = issue.game
    paths = ["/games/#{game.id}", "/games/schedule?date=#{date}",
             "/games/betting?date=#{date}", "/teams/#{game.home_team.slug}?year=#{season.year}"]
    [nil, create(:user)].each do |viewer|
      sign_in viewer if viewer
      paths.each do |path|
        get path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Synthetic Away')
        expect(response.body).to include('65') unless path.start_with?('/games/betting')
        expect(response.body).not_to match(private_details)
      end
      sign_out viewer if viewer
    end
    Ingestion::GameIssueResolution.new(issue:, user: admin, action: 'acknowledge', values: {},
                                       fingerprint: issue.comparison_fingerprint).call
    paths.each do |path|
      get path
      expect(response.body).not_to match(private_details)
    end
    sign_in admin
    get "/games/#{game.id}"
    expect(response.body).to include('Admin review')
  end
end
