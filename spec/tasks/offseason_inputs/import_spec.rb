# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require 'tmpdir'

RSpec.describe OffseasonInputs::Import do
  let(:season) { create(:season, year: 2027) }
  let(:directory) { Dir.mktmpdir('offseason-task') }

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
    FileUtils.remove_entry(directory)
  end

  def invoke
    Rake::Task['offseason_inputs:import'].reenable
    Rake::Task['offseason_inputs:import'].invoke
  end

  def prepare
    create(:team_season, season:, team: create(:team, school: 'Test College'))
    dataset = Recruiting::Dataset.new(Rails.root.join('spec/fixtures/recruiting/partial.json').binread, 'source')
    path = dataset.save(directory)
    report = Recruiting::Preview.new(dataset, season).call
    review = report.slice('dataset_revision', 'mapping_revision').merge('approved_by' => 'Task reviewer',
                                                                        'approved_at' => '2026-10-13T12:00:00Z')
    review_path = Recruiting::MappingReview.new(report).save(directory, review)
    paths = { dataset_dir: path, review_path: }
    hash = Departures::Contract.digest(OffseasonInputs::RecruitingBundle.new(paths, season).call)
    ENV.update('YEAR' => '2027', 'KIND' => 'recruiting', 'DATASET_DIR' => path, 'REVIEW_PATH' => review_path,
               'VERSION' => 'review-task-1', 'REASON' => 'Reviewed annual evidence', 'INPUT_HASH' => hash)
    described_class.new(season:, kind: 'recruiting', paths:,
                        publication: { version: 'review-task-1', reason: 'Reviewed annual evidence',
                                       input_hash: hash, predecessor_id: nil })
  end

  it 'requires explicit existing year and fails without publication' do
    expect { invoke }.to raise_error(SystemExit)
    ENV['YEAR'] = '2027'
    expect { invoke }.to raise_error(SystemExit)
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'prints coverage and a key without writes then applies only with that key' do
    importer = prepare
    key = importer.preview.fetch('preview_key')
    expect { invoke }.to output(/preview_key.*coverage.*team_inputs/m).to_stdout
    expect(OffseasonInputRevision.count).to eq(0)
    ENV['APPLY'] = 'true'
    ENV['PREVIEW_KEY'] = key
    expect { invoke }.to output(/preview_key/).to_stdout
    expect(OffseasonInputRevision.count).to eq(1)
    expect([PreseasonPrior.count, Prediction.count, TeamRatingSnapshot.count]).to eq([0, 0, 0])
  end
end
