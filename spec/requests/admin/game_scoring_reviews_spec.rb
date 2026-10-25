# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin scoring discrepancy review' do
  include Devise::Test::IntegrationHelpers

  include_context 'with scoring review evidence'

  let(:path) { admin_schedule_refresh_run_game_scoring_review_path(run, observation) }

  before { sign_in admin }

  it 'shows source totals, arithmetic, box counts and a reported-score default without a reason input' do
    get path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Synthetic Home', 'Synthetic Away', '65', '63', 'Reported game score', 'Free throws made')
    expect(response.parsed_body.at_css('input[name="choices[home]"][value="65"][checked]')).to be_present
    expect(response.parsed_body.css('textarea, input[name*="reason"]')).to be_empty
    expect(Game.count).to eq(0)
  end

  it 'previews the changed result before explicit approval and imports with no reason field' do
    post preview_admin_schedule_refresh_run_game_scoring_review_path(run, observation), params: { choices: { home: '63' } }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('63', '64', 'changes the reported result', 'Synthetic Away')
    expect(Game.count).to eq(0)
    patch path, params: { choices: { home: '63' }, confirmed: '1' }
    expect(response).to redirect_to(path)
    follow_redirect!
    expect(response.body).to include('Approved by admin', 'Imported game', 'Synthetic Away')
    expect(GameScoringReview.sole.game).to have_attributes(home_team_score: 63, away_team_score: 64)
  end

  it 'requires confirmation on the final import endpoint' do
    patch path, params: { choices: { home: '65' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Game.count).to eq(0)
  end

  it 'shows the accepted review on the original run without claiming the unfinished date completed' do
    review = approve
    get admin_schedule_refresh_run_path(run)
    expect(response.body).to include('Reviewed and imported', game_path(review.game), path)
    expect(run.reload.pending_dates).to eq([date.iso8601])
  end

  it 'links eligible rejections to the explicit review step' do
    observation
    get admin_schedule_refresh_run_path(run)
    expect(response.parsed_body.at_css("a[href='#{path}']")).to be_present
    expect(response.body).to include('Resolve scoring discrepancy')
  end

  it 'rejects forged choices without persisting a partial approval' do
    patch path, params: { choices: { home: '999' }, confirmed: '1' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(GameScoringReview.count).to eq(0)
  end

  it 'does not allow a rejection outside the run evidence' do
    observation
    run.update!(report: {})
    get path
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects non-admin requests for both reading and importing' do
    observation
    sign_in create(:user)
    get path
    expect(response).to have_http_status(:not_found)
    patch path, params: { choices: { home: '65' }, confirmed: '1' }
    expect(response).to have_http_status(:not_found)
    expect(GameScoringReview.count).to eq(0)
  end

  it 'requires authentication' do
    observation
    sign_out admin
    get path
    expect(response).to redirect_to(new_user_session_path)
  end

  it 'keeps unrelated invalid stats visible without offering approval' do
    boxes.first['teamStats']['rebounds']['total'] = 31
    boxes.last['opponentStats']['rebounds']['total'] = 31
    get path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('cannot be resolved by scoring review')
    expect(response.parsed_body.css('form')).to be_empty
  end

  it 'shows actionable contention and allows a repeated approval after the competing import finishes' do
    observation
    lock_connection = PG.connect(ENV.fetch('TEST_DATABASE_URL'))
    key_sql = GoodJob::Job.send(:advisory_lock_bigint_sql, '$1::text')
    lock_connection.exec_params("SELECT pg_advisory_lock(#{key_sql})", ["games-ingestion:#{date}"])
    begin
      patch path, params: { choices: { home: '65' }, confirmed: '1' }
      expect(response).to have_http_status(:conflict)
      expect(response.body).to include('Another game import is running', 'try again')
      expect(GameScoringReview.count).to eq(0)
    ensure
      lock_connection.close
    end
    patch path, params: { choices: { home: '65' }, confirmed: '1' }
    expect(response).to redirect_to(path)
    patch path, params: { choices: { home: '65' }, confirmed: '1' }
    expect(response).to redirect_to(path)
    expect([Game.count, GameScoringReview.count]).to eq([1, 1])
  end
end
