# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Membership review form submission', type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:season) { create(:season, year: 2027) }
  let!(:team) { create(:team, school: 'Form U', url: '/cbb/schools/form/men/') }
  let!(:conference) { create(:conference, name: 'Form Conference', slug: 'form-conf', abbreviation: 'FORM') }
  let(:path) { "/admin/season/#{season.id}/review_memberships" }
  let(:scraper) do
    instance_double(Scraper::ConferenceStandingsScraper, source_url: 'https://example.test/standings', call: [
                      { team_slug: 'form', team_name: team.school, conference_slug: 'form-conf',
                        conference_name: conference.name, conference_abbreviation: 'FORM' }
                    ])
  end

  before do
    sign_in create(:user, :admin)
    SeasonPreparer.new(year: season.year).call
    create(:team_alias, team:, value: team.school)
    allow(Scraper::ConferenceStandingsScraper).to receive(:new).and_return(scraper)
  end

  # Submit serialized controls without a clicked submit button's name/value.
  def form_values(form)
    checkable_types = %w[checkbox radio]
    pairs = form.css('input, select, textarea').filter_map do |field|
      next if field['disabled'] || !field['name']
      next if checkable_types.include?(field['type']) && !field['checked']

      [field['name'], control_value(field)]
    end
    Rack::Utils.parse_nested_query(URI.encode_www_form(pairs))
  end

  def control_value(field)
    case field.name
    when 'select' then (field.at_css('option[selected]') || field.at_css('option'))['value']
    when 'textarea' then field.content
    else field['value'].to_s
    end
  end

  def review_form
    SeasonMembershipReview.new(season).refresh
    get path
    response.parsed_body.at_css('form#membership-review-form')
  end

  it 'routes discovery from the rendered form even when submission omits button values' do
    get path
    form = response.parsed_body.at_css('form#membership-refresh-form')
    expect(form['data-turbo']).to eq('false')
    post form['action'], params: form_values(form)
    expect(response).to redirect_to(path)
    expect(season.reload.membership_proposal).to be_present
  end

  it 'routes previous-year discovery through its own form URL' do
    get path
    form = response.parsed_body.at_css('form#membership-previous-form')
    post form['action'], params: form_values(form)
    expect(response).to redirect_to(path)
    expect(season.reload.membership_proposal).to include('source_year' => 2026, 'target_year' => 2027)
  end

  it 'approves a fresh season using the rendered form action without an operation in the body' do
    form = review_form
    values = form_values(form)
    expect(values).not_to have_key('operation')
    expect(form['data-turbo']).to eq('false')
    post form['action'], params: values
    expect(response).to redirect_to(path)
    expect(season.reload.participation_review).to include('evidence' => 'Manual Review')
    expect(season.participation_review.fetch('membership_decisions').sole.fetch('reason')).to eq(
      'Reviewed source membership: https://example.test/standings'
    )
  end

  it 'defaults an established season to selected corrections without relying on the submitter value' do
    season.update!(current: true)
    form = review_form
    values = form_values(form)
    values['review']['confirm_memberships_only'] = '1'
    values['review']['teams'][team.id.to_s]['selected'] = '1'
    post form['action'], params: values
    expect(response).to redirect_to(path)
    expect(season.reload.membership_corrections.size).to eq(1)
    expect(season.participation_review).to eq({})
  end

  it 'routes corrections on a fresh season through the explicit correction button URL' do
    form = review_form
    button = form.css('button').find { |candidate| candidate.text == 'Apply selected conference corrections only' }
    values = form_values(form)
    values['review']['confirm_memberships_only'] = '1'
    values['review']['teams'][team.id.to_s]['selected'] = '1'
    expect(button['name']).to be_nil
    post button['formaction'], params: values
    expect(response).to redirect_to(path)
    expect(season.reload.membership_corrections.size).to eq(1)
    expect(season.participation_review).to eq({})
  end

  it 'records manual corrections without per-school or overall evidence inputs' do
    season.update!(current: true)
    other_conference = create(:conference, name: 'Reviewed Conference')
    form = review_form
    expect(form.css('[name="review[evidence]"], [name$="[reason]"]')).to be_empty
    expect(form.at_css('#select-all-corrections')['onchange']).to include('.membership-correction-selection')
    expect(form.css('input.membership-correction-selection').size).to eq(1)
    values = form_values(form)
    values['review']['confirm_memberships_only'] = '1'
    values['review']['teams'][team.id.to_s].merge!('selected' => '1', 'choice' => other_conference.id.to_s)
    post form['action'], params: values
    expect(response).to redirect_to(path)
    audit = season.reload.membership_corrections.sole
    expect(audit).to include('evidence' => 'Manual Review')
    expect(audit.fetch('decisions').sole).to include('reason' => 'Manual Review')
    expect(team.conference_for(season)).to eq(other_conference)
  end

  it 'explains missing row selections and preserves the confirmation without changing memberships' do
    season.update!(current: true)
    form = review_form
    values = form_values(form)
    values['review']['confirm_memberships_only'] = '1'
    post form['action'], params: values
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Select at least one school using its row checkbox')
    expect(response.parsed_body.at_css('input[name="review[confirm_memberships_only]"]')['checked']).to be_present
    expect(TeamConference.count).to eq(0)
  end
end
