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

  it 'creates the original annual extract from saved HTML without database inputs' do
    Dir.mktmpdir do |root|
      manifest = { 'observed_at' => '2026-10-11T00:00:00Z', 'retrieved_at' => '2026-10-11T00:00:00Z',
                   'captured_at' => '2026-10-11T00:00:00Z',
                   'pages' => [{ 'path' => Rails.root.join('spec/fixtures/recruiting/page1.html').to_s,
                                 'url' => Recruiting::HtmlPage.source_url(2026) }] }
      input = File.join(root, 'pages.json')
      File.write(input, JSON.generate(manifest))
      ENV.update('PAGES_PATH' => input, 'SOURCE_YEAR' => '2026', 'YEAR' => '2027',
                 'CATEGORY' => 'recruit_composite', 'OUTPUT_DIR' => File.join(root, 'output'))
      expect { Rake::Task['recruiting:acquire'].invoke }.to output(/"source_status": "ok"/).to_stdout
      path = Dir.glob(File.join(root, 'output', '*')).first
      expect(Recruiting::Dataset.load(path).manifest.dig('rows', 0, 'raw', 'team_label')).to eq('Arkansas')
      expect(Team.count).to eq(0)
    end
  end

  it 'preserves failed live acquisition and exits nonzero' do
    allow(Recruiting::Acquisition).to receive(:sleep)
    allow(HTTParty).to receive(:get).and_return(double(code: 403, body: 'Access denied'))
    ENV.delete('PAGES_PATH')
    Dir.mktmpdir do |root|
      ENV.update('SOURCE_YEAR' => '2026', 'YEAR' => '2027', 'CATEGORY' => 'recruit_composite', 'OUTPUT_DIR' => root)
      expect do
        expect { Rake::Task['recruiting:acquire'].invoke }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(/"source_status": "access_failure"/).to_stdout.and output(/Acquisition failed/).to_stderr
      expect(Dir.glob(File.join(root, 'failed-*', 'snapshot')).size).to eq(1)
    end
  end
end
