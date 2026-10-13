# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require 'tmpdir'

RSpec.describe Departures::AnnualDataset do
  let(:directory) { Dir.mktmpdir('departure-tasks') }
  let(:capture_dir) { File.join(directory, 'capture') }
  let(:plan) do
    { 'draft_year' => 2025, 'prior_season_year' => 2025, 'target_year' => 2026, 'expected_picks' => (1..60).to_a,
      'sources' => [{ 'id' => 'draft', 'type' => 'nba_results', 'url' => 'https://www.nba.com/news/2025-nba-draft-order' }] }
  end

  around do |example|
    original_rake = Rake.application
    original_env = ENV.to_h
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join('lib/tasks/departures.rake')
    ENV['PLAN_PATH'] = File.join(directory, 'plan.json')
    File.write(ENV.fetch('PLAN_PATH'), JSON.generate(plan))
    ENV['OUTPUT_DIR'] = capture_dir
    ENV['CAPTURE_DIR'] = capture_dir
    ENV['DATASET_PATH'] = File.join(capture_dir, 'dataset.json')
    example.run
  ensure
    Rake.application = original_rake
    ENV.replace(original_env)
    FileUtils.remove_entry(directory)
  end

  before do
    response = instance_double(HTTParty::Response, code: 200, body: Rails.root.join('spec/fixtures/departures/draft.html').binread)
    allow(HTTParty).to receive(:get).and_return(response)
  end

  def invoke(name)
    Rake::Task["departures:#{name}"].reenable
    Rake::Task["departures:#{name}"].invoke
  end

  it 'acquires, replays unchanged bytes and previews unknowns without any teams or database writes' do
    expect { invoke('acquire') }.to output(/dataset_revision/).to_stdout
    bytes = File.binread(ENV.fetch('DATASET_PATH'))
    allow(HTTParty).to receive(:get).and_raise('Unexpected network on replay')
    expect { invoke('replay') }.to output(/dataset_revision/).to_stdout
    expect(File.binread(ENV.fetch('DATASET_PATH'))).to eq(bytes)
    expect do
      expect { invoke('preview') }.to raise_error(SystemExit)
    end.to output(/"coverage_complete": false/).to_stdout.and output(/Incomplete departure/).to_stderr
  end

  it 'preserves blocked raw evidence and stops with a partial dataset' do
    allow(HTTParty).to receive(:get).and_return(instance_double(HTTParty::Response, code: 403, body: 'Blocked'))
    expect do
      expect { invoke('acquire') }.to raise_error(SystemExit)
    end.to output(/HTTP 403/).to_stdout.and output(/Partial acquisition/).to_stderr
    dataset = JSON.parse(File.read(ENV.fetch('DATASET_PATH')))
    expect(dataset.fetch('failures').size).to eq(1)
    expect { invoke('acquire') }.to raise_error(ArgumentError, /already exists/)
  end

  [EOFError, OpenSSL::SSL::SSLError].each do |transport_error|
    it "retains successful capture provenance after later #{transport_error} failure" do
      proof_url = 'https://school.example/participation-proof'
      plan.fetch('sources') << { 'id' => 'proof', 'type' => 'evidence', 'url' => proof_url }
      File.write(ENV.fetch('PLAN_PATH'), JSON.generate(plan))
      allow(HTTParty).to receive(:get).with(proof_url, timeout: 30, follow_redirects: false).and_raise(transport_error)
      expect do
        expect { invoke('acquire') }.to raise_error(SystemExit)
      end.to output(/Request failed/).to_stdout.and output(/Partial acquisition/).to_stderr
      manifest = JSON.parse(File.read(File.join(capture_dir, 'manifest.json')))
      dataset = JSON.parse(File.read(ENV.fetch('DATASET_PATH')))
      expect(manifest.fetch('sources').first).to include('url' => plan.fetch('sources').first.fetch('url'), 'http_status' => 200)
      expect(manifest.fetch('sources').first.fetch('captured_at')).to be_present
      expect(dataset.fetch('selections').size).to eq(60)
    end
  end

  it 'refuses a tampered normalized dataset before preview' do
    expect { invoke('acquire') }.to output.to_stdout
    File.write(ENV.fetch('DATASET_PATH'), '{}')
    expect { invoke('preview') }.to raise_error(ArgumentError, /differs from source replay/)
  end
end
