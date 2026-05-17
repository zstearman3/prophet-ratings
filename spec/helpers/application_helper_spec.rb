# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationHelper do
  let(:request) do
    instance_double(
      ActionDispatch::Request,
      base_url: 'https://prophetratings.com',
      path: '/games',
      original_url: 'https://prophetratings.com/games?weekend=true'
    )
  end

  before do
    allow(helper).to receive(:request).and_return(request)
  end

  describe '#page_title' do
    it 'returns the default title when no override is present' do
      expect(helper.page_title).to eq(described_class::DEFAULT_PAGE_TITLE)
    end

    it 'returns the provided title override' do
      helper.content_for(:page_title, 'Saturday Slate Picks')

      expect(helper.page_title).to eq('Saturday Slate Picks')
    end
  end

  describe '#page_description' do
    it 'returns the default description when no override is present' do
      expect(helper.page_description).to eq(described_class::DEFAULT_PAGE_DESCRIPTION)
    end

    it 'returns the provided description override' do
      helper.content_for(:page_description, 'Daily projections for every top matchup.')

      expect(helper.page_description).to eq('Daily projections for every top matchup.')
    end
  end

  describe '#canonical_url' do
    it 'strips query params from the canonical url' do
      expect(helper.canonical_url).to eq('https://prophetratings.com/games')
    end
  end

  describe '#page_url' do
    it 'returns the request url for sharing metadata' do
      expect(helper.page_url).to eq('https://prophetratings.com/games?weekend=true')
    end
  end

  describe '#page_image_url' do
    it 'returns an absolute social preview image url' do
      expect(helper.page_image_url).to eq('https://prophetratings.com/social-preview.png')
    end
  end
end
