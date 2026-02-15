# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SyncFullSeasonGamesJob do
  let(:scraper) { instance_double(Scraper::GamesScraper, game_count: 0) }
  let(:today) { Date.current }
  let(:season) do
    create(
      :season,
      year: 2099,
      start_date: today - 5.days,
      end_date: today - 1.day
    )
  end

  before do
    allow(Scraper::GamesScraper).to receive(:new).and_return(scraper)
  end

  it 'resumes from the latest imported game date when resume is enabled' do
    latest_imported_date = season.start_date + 3.days
    create(:game, season:, start_time: latest_imported_date + 12.hours, home_team_name: 'H1', away_team_name: 'A1')

    called_dates = []
    allow(Scraper::GamesScraper).to receive(:new) do |date|
      called_dates << date
      scraper
    end

    described_class.perform_now(season, resume: true)

    expect(called_dates).to eq((latest_imported_date..season.end_date).to_a)
  end

  it 'honors explicit date window overrides' do
    called_dates = []
    allow(Scraper::GamesScraper).to receive(:new) do |date|
      called_dates << date
      scraper
    end

    described_class.perform_now(
      season,
      start_date: season.start_date + 1.day,
      end_date: season.start_date + 2.days,
      resume: true
    )

    expect(called_dates).to eq([(season.start_date + 1.day), (season.start_date + 2.days)])
  end

  it 'skips syncing when computed range is empty' do
    described_class.perform_now(
      season,
      start_date: season.end_date + 1.day,
      end_date: season.end_date
    )

    expect(Scraper::GamesScraper).not_to have_received(:new)
  end
end
