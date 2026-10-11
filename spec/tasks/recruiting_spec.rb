# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe Recruiting, type: :task do
  let(:extract_path) { Rails.root.join('spec/fixtures/recruiting/partial.json').to_s }

  around do |example|
    original_rake = Rake.application
    original_env = ENV.to_h
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join('lib/tasks/recruiting.rake')
    example.run
  ensure
    Rake.application = original_rake
    ENV.replace(original_env)
  end

  it 'prepares and previews saved evidence, then records a pinned review without domain writes' do
    create(:season, year: 2027)
    create(:team, school: 'Test College')
    Dir.mktmpdir do |root|
      ENV.update('EXTRACT_PATH' => extract_path, 'SNAPSHOT_PATH' => extract_path, 'OUTPUT_DIR' => root)
      expect { Rake::Task['recruiting:prepare'].invoke }.to output(/#{root}/).to_stdout
      ENV.update('YEAR' => '2027', 'DATASET_DIR' => Dir.glob(File.join(root, '*')).first)
      expect { Rake::Task['recruiting:preview'].invoke }.to output(/"eligible_rows": 1/).to_stdout
      report = Recruiting::Preview.new(Recruiting::Dataset.load(ENV.fetch('DATASET_DIR')), Season.find_by!(year: 2027)).call
      approval = report.slice('dataset_revision', 'mapping_revision').merge('approved_by' => 'Test reviewer',
                                                                            'approved_at' => '2026-10-10T20:00:00Z')
      review_path = File.join(root, 'review.json')
      File.write(review_path, JSON.generate(approval))
      ENV.update('REVIEW_PATH' => review_path, 'MAPPING_DIR' => File.join(root, 'mappings'))
      Rake::Task['recruiting:preview'].reenable
      expect { Rake::Task['recruiting:preview'].invoke }.to output(/mappings.*json/m).to_stdout
      expect(TeamOffseasonProfile.count).to eq(0)
      expect(TeamRatingSnapshot.count).to eq(0)
    end
  end

  it 'reports a file/access failure with a nonzero exit' do
    ENV.update('EXTRACT_PATH' => '/no-such-recruiting-extract')
    expect do
      expect { Rake::Task['recruiting:prepare'].invoke }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(%r{source/prepare failure}).to_stderr
  end

  it 'requires an explicit existing target season' do
    ENV.delete('YEAR')
    expect do
      expect { Rake::Task['recruiting:preview'].invoke }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(%r{source/preview failure}).to_stderr
  end
end
