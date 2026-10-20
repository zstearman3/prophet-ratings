# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Conferences' do
  let!(:season_start) { create(:season, year: 2025) }
  let!(:current_season) do
    create(:season, :current, year: 2026, name: '2025-26', start_date: Date.new(2025, 11, 1), end_date: Date.new(2026, 4, 10))
  end
  let!(:next_season) { create(:season, year: 2027) }
  let!(:conference) { create(:conference, name: 'Big Test Conference') }

  before do
    [
      ['Alpha University', { rating: 25.125, overall_rank: 4, adj_offensive_efficiency: 115.25,
                             three_pt_attempt_rate: 0.4 }],
      ['Beta University', { rating: 10.5, overall_rank: 12, three_pt_attempt_rate: 0.25 }],
      ['Gamma University', { rating: 0, overall_rank: nil, three_pt_attempt_rate: 0.55 }]
    ].each do |school, attributes|
      team = create(:team, school:)
      create(:team_conference, team:, conference:, start_season: season_start)
      create(:team_season, team:, season: current_season, **attributes)
    end
  end

  describe 'GET /conferences/:id' do
    it 'shows compact national ranks with gaps, exact values, and historical team links' do
      get conference_path(conference, season: current_season.year)

      expect(response).to have_http_status(:success)
      document = response.parsed_body
      expect(document.css('a').map(&:text)).not_to include('← Conferences')
      expect(document.css('thead th').map { |cell| cell.text.strip }).to eq(['National rank', 'School', 'Rating'])
      expected_rows = [
        ['4', 'Alpha University', '25.125'],
        ['12', 'Beta University', '10.5'],
        ['—', 'Gamma University', '0.0']
      ]
      rows = document.css('tbody tr').map { |row| row.css('td').map { |cell| cell.text.strip } }
      expect(rows).to eq(expected_rows)
      expect(document.css('tbody a').first['href']).to include("year=#{current_season.year}")
      expect(document.at_css('thead th')['class']).to include('break-words')
      expect(document.css('tbody tr td:nth-child(2)').last['class']).to include('break-words')
      expect(document.css('table colgroup col').pluck('class')).to eq(['w-16', nil, 'w-[4.5rem]'])
      expect(document.css('thead th').pluck('class')).to all(include('px-1'))
      expect(document.css('tbody td').pluck('class')).to all(include('px-1'))
      expect(document.text).to include('2025-26 season')
    end

    it 'filters members and links by the requested historical season' do
      transfer = create(:team, school: 'Delta University')
      create(:team_conference, team: transfer, conference:, start_season: current_season)
      create(:team_season, team: transfer, season: current_season, rating: 7, overall_rank: 20)
      outsider = create(:team, school: 'Outside University')
      create(:team_season, team: outsider, season: current_season, rating: 99, overall_rank: 1)

      get conference_path(conference, season: season_start.year)

      expect(response).to have_http_status(:success)
      schools = response.parsed_body.css('tbody tr td:nth-child(2)').map { |cell| cell.text.strip }
      expect(schools).not_to include('Delta University', 'Outside University')

      get conference_path(conference, season: current_season.year)
      expect(response.parsed_body.css('tbody tr td:nth-child(2)').map { |cell| cell.text.strip })
        .to include('Delta University')
    end

    it 'expands to every home stats column and collapses back to compact mode' do
      get conference_path(conference, season: current_season.year)

      expand_link = response.parsed_body.css('a').find { |anchor| anchor.text == 'Show more stats' }
      expect(expand_link['href']).to include("season=#{current_season.year}", 'stats=more')
      get expand_link['href']

      document = response.parsed_body
      headers = document.css('thead th').map { |cell| cell.text.strip.sub(/[▲▼]\z/, '') }
      expect(headers.length).to eq(31)
      expect(headers.first(3)).to eq(['National rank', 'School', 'Rating'])
      expect(document.css('[tabindex="0"][aria-label*="Scroll"]').size).to eq(1)
      columns = document.css('table colgroup col').pluck('class')
      expect(columns).to eq(['w-[4.5rem]', 'w-48'])
      rank_header = document.css('thead th').first
      school_header = document.css('thead th')[1]
      expect(rank_header['class']).to include('sm:sticky', 'sm:left-0', 'whitespace-normal')
      expect(school_header['class']).to include('sm:sticky', 'sm:left-[4.5rem]', 'w-48')
      expect(rank_header['class']).not_to include('sticky left-0')
      expect(school_header['class']).not_to include('sticky left-[60px]')
      sort_link = document.css('thead a').find { |anchor| anchor.text.include?('Adj ORtg') }
      expect(sort_link['href']).to include("season=#{current_season.year}", 'stats=more')

      collapse_link = document.css('a').find { |anchor| anchor.text == 'Show fewer stats' }
      expect(collapse_link['href']).to include("season=#{current_season.year}")
      get collapse_link['href']

      expect(response.parsed_body.css('thead th').size).to eq(3)
    end

    it 'orders conference NULL values last and supports school and raw three-point attempt sorting' do
      unmeasured_team = create(:team, school: 'Null University')
      create(:team_conference, team: unmeasured_team, conference:, start_season: season_start)
      create(:team_season, team: unmeasured_team, season: current_season, rating: nil, overall_rank: nil)

      get conference_path(conference, season: current_season.year, sort: 'three_pt_attempt_rate', direction: 'desc')

      expect(response.parsed_body.css('tbody tr td:nth-child(2)').map { |cell| cell.text.strip })
        .to eq(['Gamma University', 'Alpha University', 'Beta University', 'Null University'])

      get conference_path(conference, season: current_season.year, sort: 'rating', direction: 'desc')

      expect(response.parsed_body.css('tbody tr td:nth-child(2)').map { |cell| cell.text.strip }.last).to eq('Null University')

      get conference_path(conference, season: current_season.year, sort: 'school', direction: 'asc')

      expect(response.parsed_body.css('tbody tr td:nth-child(2)').map { |cell| cell.text.strip }).to eq(
        ['Alpha University', 'Beta University', 'Gamma University', 'Null University']
      )

      get conference_path(conference, season: current_season.year, sort: 'school', direction: 'desc')
      expect(response.parsed_body.css('tbody tr td:nth-child(2)').map { |cell| cell.text.strip }).to eq(
        ['Null University', 'Gamma University', 'Beta University', 'Alpha University']
      )

      get conference_path(conference, season: current_season.year, sort: 'rating', direction: 'asc')
      ranked_rows = response.parsed_body.css('tbody tr').map do |row|
        row.css('td').first(2).map { |cell| cell.text.strip }
      end
      expected_ranked_rows = [
        ['—', 'Gamma University'],
        ['12', 'Beta University'],
        ['4', 'Alpha University'],
        ['—', 'Null University']
      ]
      expect(ranked_rows).to eq(expected_ranked_rows)

      get conference_path(conference, season: current_season.year, sort: 'rating; DROP TABLE teams', direction: 'desc')
      expect(response).to have_http_status(:success)
      expect(response.parsed_body.css('tbody tr td:nth-child(2)').first.text.strip).to eq('Alpha University')
    end

    it 'returns not found for an unknown conference or explicit unknown season' do
      get conference_path(id: -1)
      expect(response).to have_http_status(:not_found)

      get conference_path(conference, season: 'not-a-year')
      expect(response).to have_http_status(:not_found)

      get conference_path(conference, season: 1900)
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'shows empty states when no current season or no conference members exist' do
    current_season.update!(current: false)
    get conference_path(conference)
    expect(response.parsed_body.text).to include('No current season is available')

    current_season.update!(current: true)
    empty_conference = create(:conference, name: 'Empty Conference')
    get conference_path(empty_conference, season: current_season.year)
    expect(response.parsed_body.text).to include('No team ratings are available')
  end

  it 'does not expose a conference directory route' do
    get '/conferences'

    expect(response).to have_http_status(:not_found)
  end

  it 'shows missing rating and rank as unavailable and retains long school names' do
    team = create(:team, school: 'University of the Very Long School Name That Must Wrap Across a Narrow Table Layout')
    create(:team_conference, team:, conference:, start_season: season_start, end_season: current_season)
    create(:team_season, team:, season: current_season, rating: nil, overall_rank: nil)
    create(:team_season, team:, season: next_season, rating: 5, overall_rank: 20)

    get conference_path(conference, season: current_season.year)

    row = response.parsed_body.css('tbody tr').find { |item| item.text.include?(team.school) }
    expect(row.css('td').map { |cell| cell.text.strip }).to eq(['—', team.school, '—'])
    expect(row.css('td')[1]['class']).to include('break-words')

    get conference_path(conference, season: current_season.year, sort: 'rating', direction: 'desc')
    expect(response.parsed_body.css('tbody tr td:nth-child(2)').last.text.strip).to eq(team.school)

    get conference_path(conference, season: next_season.year)
    expect(response.parsed_body.text).not_to include(team.school)
  end

  it 'shows conference nil values as em dashes in expanded mode while preserving observed zero' do
    team = create(:team, school: 'Expanded Missing University')
    create(:team_conference, team:, conference:, start_season: season_start)
    create(:team_season, team:, season: current_season, rating: nil, overall_rank: nil,
                         adj_offensive_efficiency: nil, adj_defensive_efficiency: 0.0)

    get conference_path(conference, season: current_season.year, stats: 'more')

    headers = response.parsed_body.css('thead th').map { |cell| cell.text.strip.sub(/[▲▼]\z/, '') }
    row = response.parsed_body.css('tbody tr').find { |item| item.text.include?(team.school) }
    values = row.css('td').map { |cell| cell.text.strip }
    expect(values[headers.index('Rating')]).to eq('—')
    expect(values[headers.index('Adj ORtg')]).to eq('—')
    expect(values[headers.index('Adj DRtg')]).to eq('0.0')
  end
end
