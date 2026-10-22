# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::BatchAcquisition do
  let(:directory) { Dir.mktmpdir('retained-captures') }

  after { FileUtils.remove_entry(directory) }

  def saved_source(id, body)
    sha = Digest::SHA256.hexdigest(body)
    File.binwrite(File.join(directory, "#{sha}.json"), body)
    { 'id' => id, 'snapshot_sha256' => sha, 'snapshot_location' => "#{sha}.json" }
  end

  it 'reads each immutable ID once while retaining new retry captures and the selected source alias' do
    reads = []
    allow(described_class).to receive(:capture_bytes).and_wrap_original do |capture, source, location|
      reads << source.fetch('id')
      capture.call(source, location)
    end
    first = saved_source('capture-1', 'failed response')
    manifest = { 'sources' => [], 'captures' => [first] }
    evidence = described_class.retained_bytes(manifest, directory, {})
    original = evidence.fetch('capture-1').deep_dup
    retry_capture = saved_source('capture-2', 'successful retry response')
    selected = retry_capture.merge('id' => 'draft')
    expanded = { 'sources' => [selected], 'captures' => [first, retry_capture] }
    2.times { described_class.retained_bytes(expanded, directory, evidence) }
    expect(reads.tally).to eq('capture-1' => 1, 'capture-2' => 1, 'draft' => 1)
    expect(evidence.keys).to contain_exactly('capture-1', 'capture-2', 'draft')
    expect(evidence.fetch('capture-1')).to eq(original)
    expect(evidence.values_at('draft', 'capture-2').map { |entry| Base64.strict_decode64(entry.fetch('snapshot_base64')) })
      .to eq(['successful retry response', 'successful retry response'])
  end
end
