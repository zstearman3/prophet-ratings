# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin departure results and college review' do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:user, :admin) }
  let(:season) { create(:season, year: 2026) }
  let(:prior_season) { create(:season, year: 2025) }
  let(:team) { create(:team, school: 'Returning College') }
  let(:new_team) { create(:team, school: 'New College') }
  let(:batch) { Departures::CapturePreparation.create(season, {}) }

  before do
    allow(PrepareDepartureValidationJob).to receive(:perform_later)
    allow(PublishDepartureValidationJob).to receive(:perform_later)
    create(:team_season, season:, team:)
    create(:team_season, season: prior_season, team:)
    create(:team_season, season:, team: new_team)
    TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: '20')
    TeamExternalIdentity.associate!(team: new_team, provider: 'cbbd', external_id: '30')
    sign_in admin
    stub_cbbd
  end

  def cbbd_picks
    picks = super.first(3)
    picks[1].merge!('athleteId' => nil, 'sourceTeamCollegeId' => nil, 'sourceTeamLocation' => 'International Club')
    picks[2].merge!('sourceTeamCollegeId' => 30, 'sourceTeamLocation' => 'New College')
    picks
  end

  def cbbd_players(scope)
    return [] if scope == 'postseason'

    [super.first.merge('points' => 100), super.third.merge('teamId' => 30, 'team' => 'New College', 'points' => 50)]
  end

  def cbbd_teams(scope)
    return [] if scope == 'postseason'

    source = super.first
    [source.deep_merge('teamStats' => { 'points' => { 'total' => 102 } }),
     source.deep_merge('teamId' => 30, 'team' => 'New College', 'teamStats' => { 'points' => { 'total' => 200 } })]
  end

  def capture
    AcquireDepartureBatchJob.perform_now(batch.attempt.id)
    PrepareDepartureValidationJob.perform_now(DepartureValidation.where(departure_batch_id: batch.id).order(:id).last.id)
    batch.reload.attempt
  end

  def confirmation
    input = response.parsed_body.at_css('input[name="draft_review[review_key]"]')
    expect(input).to be_present
    { review_key: input['value'], confirm: '1' }
  end

  it 'shows drafted players and colleges without asking for source certification or accounting decisions' do
    original = capture
    attributes = original.attributes.deep_dup
    expect { get admin_departure_batch_path(batch) }.not_to change(DepartureAcquisition, :count)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Confirm draft results and college teams', 'Synthetic 1', 'Returning College',
                                     'International Club', 'New College', 'Skipped')
    expect(response.parsed_body.at_css('[data-draft-team-review]')).to be_present
    expect(response.parsed_body.at_css('[data-points-reconciliation]')).to be_present
    expect(response.parsed_body.css('input[name^="coverage["], select[name^="review["], input[name^="preparation["]')).to be_empty
    expect(response.parsed_body.at_css('input[name="draft_review[confirm]"][type="checkbox"]')['checked']).to be_nil
    expect(original.reload.attributes).to eq(attributes)
    expect(Ingestion::Cbbd::HttpTransport).to have_received(:call).exactly(5).times
  end

  it 'shows each college contribution separately for a player with mixed production coverage' do
    missing_team = create(:team, school: 'Missing Stats College')
    create(:team_season, season:, team: missing_team)
    create(:team_season, season: prior_season, team: missing_team)
    TeamExternalIdentity.associate!(team: missing_team, provider: 'cbbd', external_id: '40')
    allow(self).to receive(:cbbd_players).and_wrap_original do |method, scope|
      rows = method.call(scope)
      next rows if scope == 'postseason'

      rows + [rows.first.merge('teamId' => 30, 'team' => 'New College'),
              rows.first.merge('teamId' => 40, 'team' => 'Missing Stats College', 'points' => nil)]
    end
    allow(self).to receive(:cbbd_teams).and_wrap_original do |method, scope|
      rows = method.call(scope)
      scope == 'postseason' ? rows : rows + [rows.first.merge('teamId' => 40, 'team' => 'Missing Stats College')]
    end
    capture
    get admin_departure_batch_path(batch)
    rows = response.parsed_body.css('[data-draft-team-review] tbody tr').select { |row| row.text.include?('Synthetic 1') }
    expect(rows.find { |row| row.text.include?('Returning College') }['data-draft-status']).to eq('included')
    expect(rows.find { |row| row.text.include?('New College') }['data-draft-status']).to eq('skipped')
    expect(rows.find { |row| row.text.include?('Missing Stats College') }['data-draft-status']).to eq('unknown_production')
  end

  it 'publishes after one results-and-teams confirmation using the existing capture and is idempotent' do
    original = capture
    attributes = original.attributes.deep_dup
    get admin_departure_batch_path(batch)
    approval = confirmation
    reviewed_players = response.parsed_body.at_css('[data-draft-team-review] table').to_html
    patch publish_admin_departure_batch_path(batch), params: { draft_review: approval }
    expect(response).to redirect_to(admin_departure_batch_path(batch))
    expect(batch.reload.status).to eq('draft')
    expect(OffseasonInputRevision.count).to eq(0)
    PublishDepartureValidationJob.perform_now(DepartureApproval.last.id)
    expect(batch.reload.status).to eq('published')
    expect(batch.revision.team_input(team.id)).to include('known_points_subtotal' => 100, 'team_points' => 102,
                                                          'loss_share' => 100.0 / 102)
    expect(batch.revision.team_input(new_team.id).fetch('loss_share')).to eq(0.0)
    expect(batch.attempt.predecessor_id).to eq(original.id)
    expect(batch.attempt.evidence).to eq(original.evidence)
    expect(original.reload.attributes).to eq(attributes)
    reads = []
    subscriber = lambda do |_name, _started, _finished, _id, event|
      reads << event.fetch(:sql) if event.fetch(:sql).match?(/SELECT "(?:departure_acquisitions|offseason_input_revisions)"\.\*/)
    end
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') { follow_redirect! }
    expect(reads).to be_empty
    expect(response.parsed_body.at_css('[data-draft-team-review] table').to_html).to eq(reviewed_players)
    expect(response.body).to include('Published inputs', 'Synthetic 1', 'Returning College', 'Skipped')
    expect(response.parsed_body.at_css('input[name="draft_review[confirm]"]')).to be_nil
    expect do
      patch publish_admin_departure_batch_path(batch), params: { draft_review: approval }
    end.not_to change(OffseasonInputRevision, :count)
    expect(Ingestion::Cbbd::HttpTransport).to have_received(:call).exactly(5).times
  end

  it 'requires confirmation and rejects a stale prior-season scope without creating a successor' do
    original = capture
    get admin_departure_batch_path(batch)
    approval = confirmation
    patch publish_admin_departure_batch_path(batch), params: { draft_review: approval.merge(confirm: '0') }
    expect(response).to have_http_status(:unprocessable_content)
    expect(batch.reload.attempt.id).to eq(original.id)
    prior_season.team_seasons.find_by!(team:).destroy!
    patch publish_admin_departure_batch_path(batch), params: { draft_review: approval }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('changed')
    expect(batch.reload.status).to eq('draft')
    expect(batch.attempt.id).to eq(original.id)
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'shows a source error instead of offering publication when postseason data is malformed' do
    allow(self).to receive(:cbbd_teams).and_wrap_original do |method, scope|
      scope == 'postseason' ? { 'invalid' => 'not a stats array' } : method.call(scope)
    end
    capture
    get admin_departure_batch_path(batch)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.css('[role="alert"]')).not_to be_empty
    expect(response.parsed_body.at_css('input[name="draft_review[confirm]"]')).to be_nil
    expect(response.body).to include('Fetch sources again')
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'authenticates the simplified publication before loading evidence' do
    sign_out admin
    patch publish_admin_departure_batch_path(999), params: { draft_review: { confirm: '1' } }
    expect(response).to redirect_to(new_user_session_path)
    sign_in create(:user)
    patch publish_admin_departure_batch_path(999), params: { draft_review: { confirm: '1' } }
    expect(response).to have_http_status(:not_found)
  end
end
