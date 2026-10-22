# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require 'tmpdir'

RSpec.describe Departures::AnnualDataset do
  let(:directory) { Dir.mktmpdir('departure-tasks') }
  let(:capture_dir) { File.join(directory, 'capture') }
  let(:plan) do
    { 'provider' => 'cbbd', 'schema' => Departures::CbbdDataset::VERSION, 'extraction_version' => Departures::CbbdDataset::EXTRACTION,
      'draft_year' => 2025, 'prior_season_year' => 2025, 'target_year' => 2026, 'expected_picks' => (1..60).to_a,
      'scope_evidence' => 'Reviewed synthetic final regular and postseason', 'max_requests' => 15, 'retries' => 2 }
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

  before { stub_cbbd }

  def invoke(name)
    Rake::Task["departures:#{name}"].reenable
    Rake::Task["departures:#{name}"].invoke
  end

  it 'acquires, replays unchanged bytes and previews unknowns without any teams or database writes' do
    expect { invoke('acquire') }.to output(/dataset_revision/).to_stdout
    bytes = File.binread(ENV.fetch('DATASET_PATH'))
    allow(Ingestion::Cbbd::HttpTransport).to receive(:call).and_raise('Unexpected network on replay')
    expect { invoke('replay') }.to output(/dataset_revision/).to_stdout
    expect(File.binread(ENV.fetch('DATASET_PATH'))).to eq(bytes)
    expect do
      expect { invoke('preview') }.to raise_error(SystemExit)
    end.to output(/"coverage_complete": false/).to_stdout.and output(/Incomplete departure/).to_stderr
  end

  it 'preserves blocked raw evidence and stops with a partial dataset' do
    allow(Ingestion::Cbbd::HttpTransport).to receive(:call).and_return({ status: 403, body: 'Blocked', headers: {} })
    expect do
      expect { invoke('acquire') }.to raise_error(SystemExit)
    end.to output(/authentication/).to_stdout.and output(/Partial acquisition/).to_stderr
    dataset = JSON.parse(File.read(ENV.fetch('DATASET_PATH')))
    expect(dataset.fetch('failures').size).to eq(5)
    expect { invoke('acquire') }.to raise_error(ArgumentError, /already exists/)
  end

  [EOFError, OpenSSL::SSL::SSLError].each do |transport_error|
    it "retains successful capture provenance after later #{transport_error} failure" do
      allow(Ingestion::Cbbd::HttpTransport).to receive(:call)
        .with(satisfy { |uri| uri.path == '/stats/player/season' }, anything).and_raise(transport_error)
      expect do
        expect { invoke('acquire') }.to raise_error(SystemExit)
      end.to output(/transport/).to_stdout.and output(/Partial acquisition/).to_stderr
      manifest = JSON.parse(File.read(File.join(capture_dir, 'manifest.json')))
      dataset = JSON.parse(File.read(ENV.fetch('DATASET_PATH')))
      expect(manifest.fetch('sources').first).to include('url' => 'https://api.collegebasketballdata.com/draft/picks?year=2025',
                                                         'http_status' => 200)
      expect(manifest.fetch('sources').first.fetch('captured_at')).to be_present
      expect(dataset.fetch('selections').size).to eq(60)
    end
  end

  it 'refuses a tampered normalized dataset before preview' do
    expect { invoke('acquire') }.to output.to_stdout
    File.write(ENV.fetch('DATASET_PATH'), '{}')
    expect { invoke('preview') }.to raise_error(ArgumentError, /differs from source replay/)
  end

  it 'refuses a new legacy HTML acquisition before contacting a source' do
    File.write(ENV.fetch('PLAN_PATH'), JSON.generate(plan.except('provider', 'schema', 'extraction_version')))
    expect { invoke('acquire') }.to raise_error(ArgumentError, /provider|contract/)
    expect(File).not_to exist(capture_dir)
  end

  it 'retains the complete partial ledger and original body hashes if the final manifest write is interrupted' do
    final = File.join(capture_dir, 'manifest.json')
    allow(Departures::Contract).to receive(:write_bytes).and_call_original
    allow(Departures::Contract).to receive(:write_bytes).with(final, anything) do |path, bytes|
      File.binwrite(path, bytes[0, 12])
      raise Interrupt, 'Synthetic final-manifest interruption'
    end
    expect { invoke('acquire') }.to raise_error(Interrupt)
    partial = JSON.parse(File.read(File.join(capture_dir, 'manifest.partial.json')))
    expect(partial.fetch('captures').size).to eq(5)
    expect(partial.fetch('captures')).to all(satisfy do |capture|
      bytes = File.binread(File.join(capture_dir, capture.fetch('snapshot_location')))
      Digest::SHA256.hexdigest(bytes) == capture.fetch('snapshot_sha256')
    end)
    expect(Dir.children(capture_dir).grep(/departure-checkpoint/)).to be_empty
  end
end
