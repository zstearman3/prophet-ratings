# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe SeasonConferenceAlignment do
  let(:rows) do
    [{ team_slug: 'first', team_name: 'First University', conference_slug: 'alpha',
       conference_name: 'Alpha Conference', conference_abbreviation: 'ALP' }]
  end
  let(:scraper) { instance_double(Scraper::ConferenceStandingsScraper, call: rows, source_url: 'https://example.test/2026-standings.html') }

  around do |example|
    original_rake = Rake.application
    original_env = ENV.to_h
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    %w[conference_alignment season_bootstrap game_dedupe].each do |task_file|
      load Rails.root.join("lib/tasks/#{task_file}.rake")
    end
    %w[YEAR START_DATE END_DATE SYNC_GAMES DEDUPE_GAMES RUN_PRESEASON RUN_RATINGS ALIGN_CONFERENCES].each { |key| ENV.delete(key) }
    example.run
  ensure
    Rake.application = original_rake
    ENV.replace(original_env)
  end

  before do
    create(:team, school: 'First University', url: '/cbb/schools/first/men/')
    create(:conference, name: 'Alpha Conference', slug: 'alpha', abbreviation: 'ALP')
    allow(Scraper::ConferenceStandingsScraper).to receive(:new).and_return(scraper)
  end

  def invoke(task)
    Rake::Task[task].invoke
  end

  it 'defaults to the greatest stored year rather than current season or insertion order' do
    create(:season, year: 2026)
    create(:season, :current, year: 2024)
    expect { invoke('season:align_conferences') }.to output(/year=2026.*source=.*2026-standings.*Created memberships: 1/m).to_stdout
    expect(Scraper::ConferenceStandingsScraper).to have_received(:new).with(year: 2026)
  end

  it 'honors an explicit YEAR' do
    create(:season, year: 2026)
    create(:season, year: 2027)
    ENV['YEAR'] = '2026'
    expect { invoke('season:align_conferences') }.to output(/year=2026/).to_stdout
    expect(Scraper::ConferenceStandingsScraper).to have_received(:new).with(year: 2026)
  end

  it 'fails clearly when no season exists' do
    expect do
      expect { invoke('season:align_conferences') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(/No stored season/).to_stderr
  end

  it 'rejects an invalid explicit year without fetching' do
    ENV['YEAR'] = '2026oops'
    expect do
      expect { invoke('season:align_conferences') }.to raise_error(SystemExit)
    end.to output(/alignment failed/).to_stderr
    expect(Scraper::ConferenceStandingsScraper).not_to have_received(:new)
  end

  it 'prints review suggestions and exits unsuccessfully after safe changes' do
    create(:season, year: 2026)
    rows << rows.first.merge(team_slug: 'unknown', team_name: 'Unknown')
    expect do
      expect do
        expect { invoke('season:align_conferences') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(/Created memberships: 1.*REVIEW REQUIRED: 1.*unmatched_team/m).to_stdout
    end.to output(/Safe changes saved.*rerun/).to_stderr
    expect(TeamConference.count).to eq(1)
  end

  it 'prepares and aligns before making the season current or performing downstream bootstrap work' do
    ENV['YEAR'] = '2026'
    allow(scraper).to receive(:call) do
      expect(Season.find_by!(year: 2026)).not_to be_current
      expect(TeamSeason.count).to eq(1)
      rows
    end
    allow(RatingsConfigVersion).to receive(:ensure_current!) do
      expect(Season.current.year).to eq(2026)
      expect(TeamConference.count).to eq(1)
      instance_double(RatingsConfigVersion, name: 'test', id: 1)
    end
    ENV['SYNC_GAMES'] = ENV['DEDUPE_GAMES'] = ENV['RUN_PRESEASON'] = ENV['RUN_RATINGS'] = 'false'
    expect { invoke('season:bootstrap') }.to output(/Season bootstrap complete/).to_stdout
  end

  it 'allows bootstrap to skip alignment explicitly while keeping it enabled by default' do
    ENV['YEAR'] = '2026'
    ENV['ALIGN_CONFERENCES'] = 'false'
    ENV['SYNC_GAMES'] = ENV['DEDUPE_GAMES'] = ENV['RUN_PRESEASON'] = ENV['RUN_RATINGS'] = 'false'
    expect { invoke('season:bootstrap') }.to output(/Season bootstrap complete/).to_stdout
    expect(Scraper::ConferenceStandingsScraper).not_to have_received(:new)
    expect(Season.current.year).to eq(2026)
  end

  context 'when bootstrap cannot finish alignment' do
    before do
      create(:season, :current, year: 2025)
      ENV['YEAR'] = '2026'
      allow(RatingsConfigVersion).to receive(:ensure_current!)
      allow(ProphetRatings::PreseasonInitializer).to receive(:new)
      allow(SyncFullSeasonGamesJob).to receive(:perform_now)
      allow(GenerateSeasonRatingsJob).to receive(:perform_now)
      allow(Rake::Task['games:dedupe']).to receive(:invoke)
    end

    it 'stops before changing current season and all downstream work when review is needed' do
      rows.first[:team_slug] = 'unknown'
      expect do
        expect { invoke('season:bootstrap') }.to raise_error(SystemExit)
      end.to output(/REVIEW REQUIRED/).to_stdout.and output(/Resolve suggestions/).to_stderr
      expect(Season.current.year).to eq(2025)
      expect(RatingsConfigVersion).not_to have_received(:ensure_current!)
      expect(ProphetRatings::PreseasonInitializer).not_to have_received(:new)
    end

    it 'does not sync, deduplicate, or generate ratings after source failure' do
      allow(scraper).to receive(:call).and_raise(Scraper::ConferenceStandingsScraper::Error, 'HTTP 403')
      expect do
        expect { invoke('season:bootstrap') }.to raise_error(SystemExit)
      end.to output(/alignment failed.*HTTP 403/).to_stderr
      expect(SyncFullSeasonGamesJob).not_to have_received(:perform_now)
      expect(Rake::Task['games:dedupe']).not_to have_received(:invoke)
      expect(GenerateSeasonRatingsJob).not_to have_received(:perform_now)
    end
  end
end
