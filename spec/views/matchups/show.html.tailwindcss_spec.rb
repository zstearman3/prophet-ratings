# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'matchups/show.html.tailwindcss' do
  before do
    assign(:team_options, [])
  end

  it 'preserves the prediction and simulation form actions' do
    render template: 'matchups/show'

    document = Nokogiri::HTML(rendered)
    form = document.at_css('form')
    buttons = form.css('button[name="action_type"]')

    expect(form['action']).to eq(submit_matchup_path)
    expect(form['method']).to eq('post')
    expect(buttons.pluck('value')).to eq(%w[predict simulate])
    expect(buttons.map { |button| button.at_css('span').text }).to eq(['Predict Outcome', 'Simulate Outcome'])
  end

  it 'preserves the matchup inputs' do
    render template: 'matchups/show'

    form = Nokogiri::HTML(rendered).at_css('form')
    expect(form.at_css('select[name="home_team_id"]')).not_to be_nil
    expect(form.at_css('select[name="away_team_id"]')).not_to be_nil
    expect(form.at_css('input[name="neutral"]')).not_to be_nil
    expect(form.at_css('input[name="upset_modifier"]')).not_to be_nil
  end

  it 'stacks full-width action buttons on mobile and preserves their icon size' do
    render template: 'matchups/show'

    document = Nokogiri::HTML(rendered)
    buttons = document.css('form button[name="action_type"]')
    wrapper = buttons.first.parent

    expect(wrapper['class'].split).to include('flex-col', 'gap-2', 'sm:flex-row', 'sm:justify-between')
    expect(buttons.length).to eq(2)
    buttons.each do |button|
      expect(button['class'].split).to include('w-full', 'sm:w-auto', 'min-h-11', 'justify-center', 'gap-2')
      expect(button.at_css('svg')['class'].split).to include('w-5', 'h-5', 'shrink-0')
    end
  end
end
