# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin sign in', type: :request do
  it 'renders a labeled sign-in form with password manager support' do
    get new_user_session_path

    expect(response).to have_http_status(:ok)
    page = response.parsed_body
    expect(page.at_css('h1').text).to eq('Admin sign in')
    expect(page.at_css('form')['action']).to eq(user_session_path)
    expect(page.at_css('label[for="user_email"]')).to be_present
    expect(page.at_css('#user_email')['autocomplete']).to eq('username')
    expect(page.at_css('label[for="user_password"]')).to be_present
    expect(page.at_css('#user_password')['autocomplete']).to eq('current-password')
    expect(page.at_css('#user_remember_me')).to be_present
    expect(page.css('a[href="/"]').find { |link| link.text == 'Back to ratings' }).to be_present
    expect(page.css('a[href*="sign_up"], a[href*="password/new"]')).to be_empty
  end

  it 'displays failed authentication feedback' do
    post user_session_path, params: { user: { email: 'admin@example.com', password: 'incorrect' } }
    follow_redirect! if response.redirect?

    page = response.parsed_body
    expect(page.at_css('[role="alert"]').text).to include('Invalid email or password.')
    expect(page.at_css('#user_password')['value']).to be_blank
  end
end
