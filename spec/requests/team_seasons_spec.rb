# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'TeamSeasons' do
  describe 'GET /' do
    let!(:season) { create(:season, :current) }
    let!(:higher_rated) do
      create(:team_season, season:, team: create(:team, school: 'Alpha University'),
                           rating: 25.125, adj_offensive_efficiency: 115.25)
    end
    let!(:lower_rated) do
      create(:team_season, season:, team: create(:team, school: 'Beta University'),
                           rating: 10.5, adj_offensive_efficiency: 101.75)
    end

    it 'renders ranked values, school links and alternating sticky identity cells' do
      get root_path

      expect(response).to have_http_status(:success)
      rows = response.parsed_body.css('turbo-frame#team_stats tbody tr')
      expect(rows.size).to eq(2)
      expect(rows.map { |row| row.css('td').first(4).map { |cell| cell.text.strip } }).to eq(
        [%w[1] + ['Alpha University', '25.125', '115.25'],
         %w[2] + ['Beta University', '10.5', '101.75']]
      )
      [higher_rated, lower_rated].each_with_index do |team_season, index|
        cells = rows[index].css('td')
        expect(cells[0]['class']).to include('sticky left-0')
        expect(cells[1]['class']).to include('sticky left-[60px]')
        expect(cells.first(2).map { |cell| cell['class'] }).to all(include(index.zero? ? 'bg-white' : 'bg-gray-50'))
        expect(cells[1].at_css('a')['href']).to eq(team_path(team_season.team))
        expect(cells[1].at_css('a')['data-turbo']).to eq('false')
      end
    end

    it 'gives each body cell one consistent separator while preserving the sticky header and overflow' do
      get root_path

      table = response.parsed_body.at_css('turbo-frame#team_stats table')
      expect(table['class']).to include('border-separate border-spacing-0')
      expect(table.parent['class']).to include('max-h-screen overflow-auto')
      expect(table.at_css('thead')['class']).to include('sticky top-0')
      expect(table.css('tbody tr.border-b')).to be_empty
      expect(table.css('tbody td').pluck('class')).to all(include('border-b border-gray-300'))
    end

    it 'keeps rating sorting links and toggles the displayed order' do
      get root_path
      link = response.parsed_body.css('thead a').find { |anchor| anchor.text == 'Rating' }
      expect(link['href']).to eq(root_path(sort: 'rating', direction: 'desc'))

      get root_path, params: { sort: 'rating', direction: 'asc' }
      document = response.parsed_body
      expect(document.css('tbody tr td:nth-child(2)').map { |cell| cell.text.strip }).to eq(
        ['Beta University', 'Alpha University']
      )
      link = document.css('thead a').find { |anchor| anchor.text == 'Rating' }
      expect(link['href']).to eq(root_path(sort: 'rating', direction: 'desc'))
      expect(link.parent.text).to include('▲')
    end
  end
end
