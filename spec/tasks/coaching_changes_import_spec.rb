# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe CoachingChangesImport do
  around do |example|
    original_rake = Rake.application
    original_env = ENV.to_h
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join('lib/tasks/coaching_changes.rake')
    ENV['YEAR'] = '2027'
    example.run
  ensure
    Rake.application = original_rake
    ENV.replace(original_env)
  end

  it 'imports and prints coverage and candidate IDs before seasons exist' do
    rows = JSON.parse(file_fixture('coaching_changes/rows.json').read).map { |row| row.fetch('value').symbolize_keys }
    scraper = instance_double(Scraper::CoachingChangesScraper, call: rows)
    allow(Scraper::CoachingChangesScraper).to receive(:new).with(year: 2027).and_return(scraper)
    expect { Rake::Task['coaching:discover'].invoke }.to output(/"d1_rows": 2.*candidate_id.*Review candidate IDs/m).to_stdout
    expect(Season.count).to eq(0)
    expect(CoachingChange.count).to eq(2)
  end

  it 'requires YEAR and never defaults to an existing season' do
    ENV.delete('YEAR')
    expect do
      expect { Rake::Task['coaching:discover'].invoke }.to raise_error(SystemExit)
    end.to output(/Coaching discovery failed/).to_stderr
  end

  it 'fails visibly without writes on source failure' do
    scraper = instance_double(Scraper::CoachingChangesScraper)
    allow(Scraper::CoachingChangesScraper).to receive(:new).and_return(scraper)
    allow(scraper).to receive(:call).and_raise(Scraper::CoachingChangesScraper::Error, 'HTTP 403')
    expect do
      expect { Rake::Task['coaching:discover'].invoke }.to raise_error(SystemExit)
    end.to output(/no import changes saved.*HTTP 403/).to_stderr
    expect(CoachingChange.count).to eq(0)
  end
end
