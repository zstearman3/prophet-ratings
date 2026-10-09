# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require 'tempfile'

RSpec.describe Importer::Setup::TeamConferencesSynchronizer do
  around do |example|
    original_rake = Rake.application
    original_env = ENV.to_h
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join('lib/tasks/import.rake')
    ENV.delete('APPLY')
    Tempfile.create(['conference-task', '.csv']) do |file|
      file.write("school,conference_slug,start_year,end_year\nAlpha,new,2025,\n")
      file.flush
      ENV['CSV_PATH'] = file.path
      example.run
    end
  ensure
    Rake.application = original_rake
    ENV.replace(original_env)
  end

  def invoke
    Rake::Task['import:reconcile_conferences'].reenable
    Rake::Task['import:reconcile_conferences'].invoke
  end

  it 'previews deletions without imports or unrelated writes and applies only on explicit request', :aggregate_failures do
    season = create(:season, :current, year: 2025)
    team = create(:team, school: 'Alpha')
    conference = create(:conference, slug: 'new')
    stale = create(:team_conference, start_season: season)
    before = [Team, Season, TeamSeason, Conference].map { |model| model.order(:id).map(&:attributes) }
    allow(Importer::Setup::BaseDataImporter).to receive(:run).and_call_original
    allow(SeasonPreparer).to receive(:new).and_call_original

    expect { invoke }.to output(/preview.*"action":"delete".*"action":"create".*APPLY=true/m).to_stdout
    expect(TeamConference.pluck(:id)).to eq([stale.id])
    ENV['APPLY'] = 'true'
    expect { invoke }.to output(/applied/).to_stdout
    expect(TeamConference.find_by!(team:, start_season: season).conference).to eq(conference)
    expect(TeamConference.exists?(stale.id)).to be(false)
    expect([Team, Season, TeamSeason, Conference].map { |model| model.order(:id).map(&:attributes) }).to eq(before)
    expect { invoke }.to output(/unchanged: 1/).to_stdout
    expect(Importer::Setup::BaseDataImporter).not_to have_received(:run)
    expect(SeasonPreparer).not_to have_received(:new)
  end

  it 'fails nonzero on invalid references without implicitly importing or preparing them' do
    allow(Importer::Setup::BaseDataImporter).to receive(:run).and_call_original
    allow(SeasonPreparer).to receive(:new).and_call_original
    expect { invoke }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    expect(Team.count + Season.count + TeamConference.count).to eq(0)
    expect(Importer::Setup::BaseDataImporter).not_to have_received(:run)
    expect(SeasonPreparer).not_to have_received(:new)
  end

  it 'rejects a misspelled apply flag before writes' do
    ENV['APPLY'] = 'yes'
    expect { invoke }.to raise_error(SystemExit)
    expect(TeamConference.count).to eq(0)
  end
end
