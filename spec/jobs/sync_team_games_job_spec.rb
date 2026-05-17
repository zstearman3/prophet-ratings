# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SyncTeamGamesJob do
  let(:today) { Date.new(2026, 2, 3) }
  let(:team) { create(:team) }
  let(:season) { create(:season, year: 2026, start_date: today - 1.day, end_date: today - 1.day) }
  let(:service) { instance_double(Ingestion::GamesIngestionService, call: { imported_rows: 1 }) }

  before do
    allow(Game).to receive(:current_schedule_date).and_return(today)
    allow(Ingestion::GamesIngestionService).to receive(:new).and_return(service)
  end

  it 'delegates team-date syncing to the ingestion service' do
    described_class.perform_now(team.id, season.id)

    expect(Ingestion::GamesIngestionService).to have_received(:new).with(date: season.start_date, team:)
    expect(service).to have_received(:call)
  end
end
