# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RailsAdmin assets', type: :request do
  it 'compiles the admin stylesheet through Sprockets with embedded Sass' do
    stylesheet = Rails.application.assets.find_asset('rails_admin/application.css')

    expect(stylesheet).to be_present
    expect(stylesheet.to_s).to include('.rails_admin', '.navbar')
  end
end
