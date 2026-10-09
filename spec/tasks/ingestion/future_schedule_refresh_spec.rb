# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe Ingestion::FutureScheduleRefresh do
  let(:season) { create(:season, year: 2027) }
  let(:service) { instance_double(described_class) }

  around do |example|
    original_rake = Rake.application
    original_env = ENV.to_h
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join('lib/tasks/season_bootstrap.rake')
    ENV['YEAR'] = '2027'
    ENV['SCHEDULE_START_DATE'] = '2027-11-01'
    ENV['SCHEDULE_END_DATE'] = '2027-11-03'
    example.run
  ensure
    Rake.application = original_rake
    ENV.replace(original_env)
  end

  def invoke
    Rake::Task['season:refresh_schedule'].invoke
  end

  it 'requires an existing explicit target season' do
    expect { invoke }.to raise_error(SystemExit, /No season found/)
    expect(Season.count).to eq(0)
  end

  it 'requires YEAR even when a current season exists' do
    create(:season, :current, year: 2027)
    ENV.delete('YEAR')
    expect { invoke }.to raise_error(SystemExit, /YEAR/)
  end

  it 'passes strict dates to the service and prints the report without activating or enqueuing ratings' do
    season
    allow(described_class).to receive(:new).and_return(service)
    allow(UpdateRankingsJob).to receive(:perform_later)
    allow(service).to receive(:call).and_return(year: 2027, days: [], absent_ids: [], failed_dates: [])
    expect { invoke }.to output(/Schedule refresh complete/).to_stdout
    expect(described_class).to have_received(:new).with(
      season:, start_date: Date.new(2027, 11, 1), end_date: Date.new(2027, 11, 3)
    )
    expect(season.reload).not_to be_current
    expect(UpdateRankingsJob).not_to have_received(:perform_later)
  end

  it 'exits nonzero for failed dates after printing their report' do
    season
    allow(described_class).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_return(year: 2027, days: [{ date: '2027-11-01', error: 'HTTP 503' }],
                                                absent_ids: [], failed_dates: ['2027-11-01'])
    expect { invoke }.to raise_error(SystemExit, /incomplete/).and output(/HTTP 503/).to_stdout
  end

  it 'rejects malformed dates' do
    season
    ENV['SCHEDULE_START_DATE'] = 'not-a-date'
    expect { invoke }.to raise_error(SystemExit, /Invalid SCHEDULE_START_DATE/)
  end

  it 'requires both bounds before requesting any source data' do
    season
    ENV.delete('SCHEDULE_END_DATE')
    expect { invoke }.to raise_error(SystemExit, /requires an ordered/)
  end
end
