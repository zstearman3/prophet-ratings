# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SyncDailyGamesJob do
  it 'delegates game ingestion to the ingestion service' do
    date = Date.new(2026, 2, 21)
    service = instance_double(Ingestion::GamesIngestionService, call: { imported_rows: 3 })
    allow(Ingestion::GamesIngestionService).to receive(:new).with(date:).and_return(service)

    described_class.perform_now(date)

    expect(service).to have_received(:call)
  end
end
