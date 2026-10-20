# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'layouts/_navbar' do
  it 'renders the four destinations with the current date in the schedule link and preserves the home logo' do
    allow(Date).to receive(:current).and_return(Date.new(2026, 10, 19))
    render partial: 'layouts/navbar'

    document = Nokogiri::HTML(rendered)
    expect(document.at_css('nav img[alt="Retro Prophet Logo"]')).not_to be_nil
    expect(document.at_css('nav > div > a')['href']).to eq(root_path)

    links = document.css('nav a[data-nav-item]')
    expect(links.map { |link| link.text.strip }).to eq(['Ratings', 'Matchup Analysis', 'Schedule', 'Betting'])
    expect(links.pluck('href')).to eq([
                                        root_path,
                                        matchup_path,
                                        schedule_games_path(date: '2026-10-19'),
                                        betting_games_path
                                      ])
  end

  {
    '/' => 'Ratings',
    '/matchup' => 'Matchup Analysis',
    '/matchup/submit' => 'Matchup Analysis',
    '/games/schedule' => 'Schedule',
    '/games/betting' => 'Betting'
  }.each do |path, label|
    it "marks only #{label} current at #{path}" do
      allow(view.request).to receive(:path).and_return(path)
      render partial: 'layouts/navbar'

      current_links = Nokogiri::HTML(rendered).css('nav a[aria-current="page"]')
      expect(current_links.map { |link| link.text.strip }).to eq([label])
      expect(current_links.first['class']).to include('bg-purple-50', 'text-prophet-indigo')
    end
  end

  it 'does not mark an unrelated path current' do
    allow(view.request).to receive(:path).and_return('/unrelated')
    render partial: 'layouts/navbar'

    expect(Nokogiri::HTML(rendered).css('nav a[aria-current="page"]')).to be_empty
  end

  it 'starts with an accessible collapsed disclosure' do
    render partial: 'layouts/navbar'
    document = Nokogiri::HTML(rendered)
    toggle = document.at_css('button[aria-controls="navbar-menu"]')

    expect(toggle['aria-expanded']).to eq('false')
    expect(toggle['aria-label']).to eq('Expand menu')
    expect(document.at_css('#navbar-menu.hidden')).not_to be_nil
  end
end
