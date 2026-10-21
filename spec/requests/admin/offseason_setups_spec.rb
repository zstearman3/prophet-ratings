# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin offseason setup' do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:user, :admin) }

  it 'requires an admin and hides the dashboard from signed-in non-admins' do
    get admin_offseason_setup_path
    expect(response).to redirect_to(new_user_session_path)

    sign_in create(:user)
    get admin_offseason_setup_path
    expect(response).to have_http_status(:not_found)

    post admin_offseason_setup_path, params: { preparation: { year: '2027' } }
    expect(response).to have_http_status(:not_found)
  end

  it 'renders an empty, read-only dashboard for an admin' do
    sign_in admin

    expect { get admin_offseason_setup_path }.not_to change(Season, :count)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Prepare a target season', 'No target season is stored yet')
  end

  it 'selects the requested season and shows the fixed sequence with honest later steps' do
    sign_in admin
    first = create(:season, year: 2025)
    selected = create(:season, year: 2027)

    get admin_offseason_setup_path(season_id: selected.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Ending year 2027', "value=\"#{selected.id}\"", 'Review memberships, participation and dates',
                                     'Review departure batches and coverage; model selection remains manual.',
                                     'Use the ending year: 2027 means the 2026–27 season.')
    document = response.parsed_body
    year_field = document.at_css('input[name="preparation[year]"]')
    expect(year_field['min']).to eq('2')
    expect(year_field['max']).to eq('9999')
    expect(year_field['required']).to eq('required')
    expect(document.at_css('label[for="preparation_start_date"]').text).to include('(optional)')
    expect(document.at_css('label[for="preparation_end_date"]').text).to include('(optional)')
    expect(document.at_css('input[type="submit"][value="View season"]')['class'].split).to eq(
      %w[bg-prophet-indigo hover:bg-prophet-indigo/80 text-white font-bold py-2 px-4 rounded inline-flex items-center space-x-2]
    )
    expect(response.body.index('Prepare target season')).to be < response.body.index('Review memberships, participation and dates')
    expect(response.body).not_to include("season_id=#{first.id}")
  end

  it 'prepares and repeats without changing existing dates or current selection' do
    sign_in admin
    team = create(:team)
    current = create(:season, :current, year: 2026)
    target = create(:season, year: 2027, start_date: Date.new(2026, 11, 5), end_date: Date.new(2027, 4, 15))
    other = create(:season, year: 2028, start_date: Date.new(2027, 11, 8), end_date: Date.new(2028, 4, 18))
    team_season = create(:team_season, season: target, team:)
    original_dates = [target.start_date, target.end_date]
    original_rating = [team_season.adj_offensive_efficiency, team_season.adj_pace]
    version = create(:ratings_config_version)
    prior = PreseasonPrior.create!(team_season:, ratings_config_version: version, inputs: { 'retained' => true },
                                   outputs: { 'pace' => 68.0 })
    team_season.update!(preseason_prior: prior, ratings_config_version: version)
    snapshot = create(:team_rating_snapshot, team_season:, team:, season: target, ratings_config_version: version,
                                             snapshot_date: Date.new(2027, 4, 15))
    game = create(:game, season: target)
    prediction = Prediction.create!(game:, home_team_snapshot: snapshot, away_team_snapshot: snapshot,
                                    ratings_config_version: version, home_win_probability: 0.5)
    history_ids = [prior.id, snapshot.id, prediction.id]

    post admin_offseason_setup_path, params: { preparation: { year: '2027', start_date: '', end_date: '' } }

    expect(response).to redirect_to(admin_offseason_setup_path(season_id: target.id))
    expect(target.reload).to have_attributes(start_date: original_dates[0], end_date: original_dates[1], current: false)
    expect(current.reload.current).to be(true)
    expect(team_season.reload.attributes.values_at('adj_offensive_efficiency', 'adj_pace')).to eq(original_rating)
    expect([team_season.preseason_prior_id, team_season.ratings_config_version_id]).to eq([prior.id, version.id])
    expect([snapshot.reload.id, target.predictions.sole.id]).to eq([history_ids[1], history_ids[2]])
    expect(other.reload.attributes.values_at('start_date', 'end_date')).to eq([Date.new(2027, 11, 8), Date.new(2028, 4, 18)])

    post admin_offseason_setup_path, params: { preparation: { year: '2027', start_date: '2026-11-06', end_date: '2027-04-16' } }
    expect(target.reload).to have_attributes(start_date: Date.new(2026, 11, 6), end_date: Date.new(2027, 4, 16))
    expect(current.reload.current).to be(true)
    expect(other.reload.attributes.values_at('start_date', 'end_date')).to eq([Date.new(2027, 11, 8), Date.new(2028, 4, 18)])
  end

  it 'preserves another season dates when only the year from the rendered form changes' do
    sign_in admin
    create(:season, :current, year: 2026)
    target = create(:season, year: 2027, start_date: Date.new(2026, 11, 9), end_date: Date.new(2027, 4, 12))

    get admin_offseason_setup_path
    fields = rendered_preparation_values
    fields['year'] = '2027'

    post admin_offseason_setup_path, params: { preparation: fields }

    expect(response).to redirect_to(admin_offseason_setup_path(season_id: target.id))
    expect(target.reload).to have_attributes(start_date: Date.new(2026, 11, 9), end_date: Date.new(2027, 4, 12))
  end

  it 'uses service defaults when only the year from the rendered form changes to a new season' do
    sign_in admin
    create(:season, :current, year: 2026, start_date: Date.new(2025, 11, 3), end_date: Date.new(2026, 4, 6))

    get admin_offseason_setup_path
    fields = rendered_preparation_values
    fields['year'] = '2027'

    post admin_offseason_setup_path, params: { preparation: fields }

    target = Season.find_by!(year: 2027)
    expect(target).to have_attributes(start_date: Date.new(2026, 11, 3), end_date: Date.new(2027, 4, 6))
  end

  it 'keeps submitted values and performs no writes for invalid dates and years' do
    sign_in admin
    before_count = Season.count

    post admin_offseason_setup_path, params: { preparation: { year: '2027', start_date: '2027-02-31', end_date: '2027-04-10' } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Start date must use a valid ISO date', '2027-02-31')
    expect(Season.count).to eq(before_count)

    post admin_offseason_setup_path, params: { preparation: { year: '1', start_date: '', end_date: '' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('2 through 9999', 'value="1"')
    expect(Season.count).to eq(before_count)
  end

  it 'rejects reversed dates before preparation' do
    sign_in admin
    expect do
      post admin_offseason_setup_path, params: { preparation: { year: '2028', start_date: '2028-04-10', end_date: '2027-11-01' } }
    end.not_to change(Season, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('End date must be after start date')
  end

  it 'renders an actionable error when the ending year is missing' do
    sign_in admin
    before_count = Season.count

    post admin_offseason_setup_path, params: { preparation: { start_date: '2027-11-01', end_date: '' } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('YEAR must be an integer from 1 to 9999')
    expect(Season.count).to eq(before_count)
  end

  def rendered_preparation_values
    form = response.parsed_body.at_css('form[action="/admin/offseason_setup"]')
    %w[year start_date end_date].to_h do |field|
      input = form.at_css("input[name='preparation[#{field}]']")
      [field, input['value']]
    end
  end
end
