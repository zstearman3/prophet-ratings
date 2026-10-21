# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::Reconciliation::Files do
  include_context 'with synthetic reconciliation'

  let(:directory) { Dir.mktmpdir('synthetic-reconciliation') }

  around do |example|
    example.run
  ensure
    FileUtils.remove_entry(directory)
  end

  before do
    game
    allow(Ingestion::Cbbd::Adapter).to receive(:replay).with(manifest: 'synthetic-manifest').and_return(replay)
  end

  def path(name)
    File.join(directory, name)
  end

  it 'writes private JSON evidence and refuses to overwrite it' do
    result = described_class.compare(manifest: 'synthetic-manifest', report: path('report.json'))
    expect(result['source_observations']).to eq(1)
    expect(File.stat(path('report.json')).mode & 0o777).to eq(0o600)
    expect(JSON.parse(File.read(path('report.json')))).to eq(report)
    expect { described_class.compare(manifest: 'synthetic-manifest', report: path('report.json')) }.to raise_error(Errno::EEXIST)
  end

  it 'round trips JSON artifacts into guarded identity-only apply' do
    described_class.compare(manifest: 'synthetic-manifest', report: path('report.json'))
    File.write(path('decisions.json'), JSON.generate(decisions))
    result = described_class.apply(manifest: 'synthetic-manifest', report: path('report.json'), decisions: path('decisions.json'))
    expect(result).to include('mappings' => 3, 'decision_id' => IdentityMappingDecision.sole.id)
  end
end
