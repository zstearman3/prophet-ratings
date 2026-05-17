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
  let(:service) { instance_double(Ingestion::GamesIngestionService, call: { imported_rows: 0 }) }

  before do
    season
    allow(Ingestion::GamesIngestionService).to receive(:new).and_return(service)
    allow(UpdateRankingsJob).to receive(:perform_later)
  end

  it 'delegates each sync date to the ingestion service' do
    described_class.perform_now(season.id)

    expect(Ingestion::GamesIngestionService).to have_received(:new).with(date: season.start_date)
    expect(service).to have_received(:call)
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
