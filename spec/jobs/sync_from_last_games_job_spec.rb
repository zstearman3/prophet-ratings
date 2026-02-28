# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SyncFromLastGamesJob do
  let(:season) do
    create(
      :season,
      :current,
      year: Date.current.year,
      start_date: Date.yesterday,
      end_date: Date.yesterday
    )
  end
  let(:scraper) { instance_double(Scraper::GamesScraper, game_count: 0) }

  before do
    season
    allow(Scraper::GamesScraper).to receive(:new).and_return(scraper)
    allow(UpdateRankingsJob).to receive(:perform_later)
  end

  it 'enqueues rankings generation after syncing' do
    described_class.perform_now(season.id)

    expect(UpdateRankingsJob).to have_received(:perform_later).with(season.id)
  end

  it 'can skip enqueuing rankings generation' do
    described_class.perform_now(season.id, enqueue_rankings: false)

    expect(UpdateRankingsJob).not_to have_received(:perform_later)
  end
end
