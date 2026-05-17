# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'games/index.html.tailwindcss' do
  it 'renders a placeholder when venue name is blank' do
    assign(
      :games,
      [
        build_stubbed(
          :game,
          start_time: Time.zone.local(2026, 1, 1, 12),
          away_team_name: 'Away',
          home_team_name: 'Home',
          away_team_score: 60,
          home_team_score: 70,
          venue_name: ''
        )
      ]
    )

    render template: 'games/index'

    venue_cell = Nokogiri::HTML(rendered).css('tbody tr td').last
    expect(venue_cell.text.strip).to eq('-')
  end
end
