# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'layouts/_navbar' do
  before { allow(view).to receive(:user_signed_in?).and_return(false) }

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

  it 'uses the requested background and hides link icons at the desktop breakpoint' do
    render partial: 'layouts/navbar'

    document = Nokogiri::HTML(rendered)
    expect(document.at_css('nav')['class'].split).to include('bg-[#F1F5F9]')
    icons = document.css('nav a[data-nav-item] svg')
    expect(icons.length).to eq(4)
    expect(icons.all? { |icon| icon['class'].split.include?('md:hidden') }).to be(true)
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
      expect(current_links.first['class']).to include('bg-purple-50', 'md:bg-transparent', 'text-prophet-indigo')
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
    expect(document.at_css('nav')['data-action'].split).to include('pointerdown->navbar#blurAlreadyFocusedControl:capture')
  end

  it 'shows admin destinations only to admins and marks the active admin link' do
    allow(view).to receive_messages(user_signed_in?: true, current_user: build_stubbed(:user, :admin))
    allow(view.request).to receive(:path).and_return('/admin/offseason_setup')

    render partial: 'layouts/navbar'

    document = Nokogiri::HTML(rendered)
    expect(document.at_css('details[data-admin-navigation][open]')).not_to be_nil
    expect(document.at_css('a[aria-current="page"]')&.text).to include('Offseason setup')
    expect(document.css('details[data-admin-navigation] a').map { |link| link.text.strip }).to eq(['Offseason setup', 'Model analysis'])
    parent_classes = document.at_css('details[data-admin-navigation]').parent['class'].split
    submenu = document.at_css('details[data-admin-navigation] > ul')
    submenu_classes = submenu['class'].split
    expect({ parent: parent_classes, submenu: submenu_classes }).to match(
      parent: include('md:relative'),
      submenu: include('ml-5', 'border-l-2', 'border-purple-200', 'pl-3', 'md:right-0', 'md:ml-0', 'md:border-l')
    )
    expect(document.at_css('nav')['data-action']).to include('keydown.esc->navbar#close')
  end

  it 'keeps the selected season and model on the readiness Model analysis navigation link' do
    season = build_stubbed(:season)
    assign(:page, { season:, report: { 'model_id' => 123 } })
    allow(view).to receive_messages(user_signed_in?: true, current_user: build_stubbed(:user, :admin),
                                    controller_path: 'admin/offseason_readiness_reviews')
    render partial: 'layouts/navbar'

    link = Nokogiri::HTML(rendered).at_xpath('//a[text()="Model analysis"]')
    expect(link['href']).to eq(admin_prediction_evaluation_path(season_id: season.id, model_id: 123))
  end

  it 'preserves the ordinary Model analysis destination outside readiness even when a page has season context' do
    assign(:page, { season: build_stubbed(:season), report: { 'model_id' => 123 } })
    allow(view).to receive_messages(user_signed_in?: true, current_user: build_stubbed(:user, :admin),
                                    controller_path: 'admin/prediction_evaluations')
    render partial: 'layouts/navbar'

    expect(Nokogiri::HTML(rendered).at_xpath('//a[text()="Model analysis"]')['href']).to eq(admin_prediction_evaluation_path)
  end

  it 'omits admin destinations for signed-in non-admins' do
    allow(view).to receive_messages(user_signed_in?: true, current_user: build_stubbed(:user))

    render partial: 'layouts/navbar'

    expect(Nokogiri::HTML(rendered).at_css('details[data-admin-navigation]')).to be_nil
  end

  it 'shows navbar focus rings only for keyboard-visible focus' do
    render partial: 'layouts/navbar'
    document = Nokogiri::HTML(rendered)
    home_link = document.at_css('nav > div > a')
    toggle = document.at_css('button[aria-controls="navbar-menu"]')
    links = document.css('nav a[data-nav-item]')

    expect(home_link['class'].split).to include('focus-visible:ring-2', 'focus-visible:ring-prophet-indigo', 'focus-visible:ring-offset-2')
    expect(toggle['class'].split).to include('focus-visible:ring-2', 'focus-visible:ring-prophet-indigo')
    expect(links.all? { |link| link['class'].split.include?('focus-visible:ring-2') }).to be(true)
  end
end
