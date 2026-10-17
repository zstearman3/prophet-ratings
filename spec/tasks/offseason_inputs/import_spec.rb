# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe OffseasonInputs::Import do
  let(:season) { create(:season, year: 2027) }

  around do |example|
    original_rake = Rake.application
    original_env = ENV.to_h
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join('lib/tasks/offseason_inputs.rake')
    %w[YEAR KIND INPUT_HASH VERSION REASON PREDECESSOR_ID PREVIEW_KEY APPLY].each { |key| ENV.delete(key) }
    example.run
  ensure
    Rake.application = original_rake
    ENV.replace(original_env)
  end

  def invoke
    Rake::Task['offseason_inputs:import'].reenable
    Rake::Task['offseason_inputs:import'].invoke
  end

  def prepare
    ENV.update('YEAR' => '2027', 'KIND' => 'departures', 'CAPTURE_DIR' => '/capture', 'DATASET_PATH' => '/capture/dataset.json',
               'REVIEW_PATH' => '/capture/review.json', 'VERSION' => 'review-task-1',
               'REASON' => 'Reviewed annual evidence', 'INPUT_HASH' => 'reviewed-hash')
    report = { 'preview_key' => 'reviewed-key', 'payload' => { 'report' => {}, 'team_inputs' => {} } }
    importer = instance_double(described_class, preview: report, call: report)
    allow(described_class).to receive(:new).with(
      season:, kind: 'departures',
      paths: { capture_dir: '/capture', dataset_path: '/capture/dataset.json', review_path: '/capture/review.json' },
      publication: { version: 'review-task-1', reason: 'Reviewed annual evidence', input_hash: 'reviewed-hash', predecessor_id: nil }
    ).and_return(importer)
    importer
  end

  it 'requires explicit existing year and fails without publication' do
    ENV['KIND'] = 'departures'
    expect { invoke }.to raise_error(SystemExit)
    ENV['YEAR'] = '2028'
    expect { invoke }.to raise_error(SystemExit)
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'passes departure file paths and the explicit preview key to the importer' do
    importer = prepare
    expect { invoke }.to output(/preview_key.*coverage.*team_inputs/m).to_stdout
    expect(OffseasonInputRevision.count).to eq(0)
    ENV['APPLY'] = 'true'
    ENV['PREVIEW_KEY'] = 'reviewed-key'
    expect { invoke }.to output(/preview_key/).to_stdout
    expect(importer).to have_received(:call).with(preview_key: 'reviewed-key')
    expect([PreseasonPrior.count, Prediction.count, TeamRatingSnapshot.count]).to eq([0, 0, 0])
  end

  it 'rejects recruiting file imports before requesting file paths or publication parameters' do
    ENV.update('YEAR' => '2027', 'KIND' => 'recruiting')
    expect { invoke }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    expect(OffseasonInputRevision.count).to eq(0)
  end
end
