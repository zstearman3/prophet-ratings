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
    allow(GenerateSeasonRatingsJob).to receive(:perform_later)
  end

  it 'enqueues ratings generation after syncing' do
    described_class.perform_now(season.id)

    expect(GenerateSeasonRatingsJob).to have_received(:perform_later).with(
      season.id,
      run_preseason: false,
      enqueue_nightly_predictions: true
    )
  end

  it 'can skip enqueuing ratings generation' do
    described_class.perform_now(season.id, enqueue_ratings: false)

    expect(GenerateSeasonRatingsJob).not_to have_received(:perform_later)
  end
end
