# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require 'tmpdir'

RSpec.describe 'cbbd tasks', type: :task do
  let(:directory) { Dir.mktmpdir('cbbd-task') }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?('cbbd:dry_run')
    allow(Importer::GamesImporter).to receive(:import)
  end

  after do
    FileUtils.remove_entry(directory)
    Rake::Task['cbbd:dry_run'].reenable
    Rake::Task['cbbd:replay'].reenable
  end

  it 'replays offline without credentials or writes and keeps incomplete exit status' do
    result = Ingestion::Cbbd::Adapter.new(
      season: 2026, start_date: '2025-11-01', end_date: '2025-11-01', capture_directory: directory,
      api_key: 'synthetic', transport: ->(_uri, _key) { { status: 401, headers: {}, body: '{}' } }
    ).call
    allow(ENV).to receive(:fetch).with('MANIFEST').and_return(result['manifest'])
    counts = [Game.count, TeamGame.count]
    expect { Rake::Task['cbbd:replay'].invoke }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    expect([Game.count, TeamGame.count]).to eq(counts)
    expect(Importer::GamesImporter).not_to have_received(:import)
  end

  it 'fails safely before requests when bounds are absent' do
    allow(ENV).to receive(:fetch).and_raise(KeyError)
    expect { Rake::Task['cbbd:dry_run'].invoke }.to raise_error(SystemExit)
  end
end
