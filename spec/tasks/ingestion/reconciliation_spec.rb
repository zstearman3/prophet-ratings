# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe Ingestion::Reconciliation do
  around do |example|
    original_rake = Rake.application
    original_env = ENV.to_h
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join('lib/tasks/cbbd.rake')
    ENV['MANIFEST'] = 'synthetic-manifest'
    ENV['REPORT'] = 'synthetic-report'
    ENV['DECISIONS'] = 'synthetic-decisions'
    example.run
  ensure
    Rake.application = original_rake
    ENV.replace(original_env)
  end

  it 'prints offline comparison coverage and guarded apply summaries' do
    allow(Ingestion::Reconciliation::Files).to receive(:compare).with(manifest: 'synthetic-manifest', report: 'synthetic-report')
                                                                .and_return('source_observations' => 2)
    allow(Ingestion::Reconciliation::Files).to receive(:apply).with(manifest: 'synthetic-manifest', report: 'synthetic-report',
                                                                    decisions: 'synthetic-decisions').and_return('decision_id' => 1)
    expect { Rake::Task['cbbd:compare'].invoke }.to output(/source_observations.*2/).to_stdout
    expect { Rake::Task['cbbd:apply_mappings'].invoke }.to output(/decision_id.*1/).to_stdout
  end

  it 'exits nonzero for missing explicit input or stale reviewed state' do
    ENV.delete('MANIFEST')
    expect { Rake::Task['cbbd:compare'].invoke }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    ENV['MANIFEST'] = 'synthetic-manifest'
    allow(Ingestion::Reconciliation::Files).to receive(:apply).and_raise(ArgumentError, 'Comparison changed')
    expect { Rake::Task['cbbd:apply_mappings'].invoke }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
  end
end
